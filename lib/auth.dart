import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart'
    show
        Chain,
        HttpMethod,
        Interceptor,
        Request,
        Response,
        StripStringExtension,
        applyHeaders;
import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:version/version.dart';
import 'package:waterflyiii/generated/l10n/app_localizations.dart';
import 'package:waterflyiii/generated/swagger_fireflyiii_api/firefly_iii.swagger.dart';
import 'package:waterflyiii/stock.dart';
import 'package:waterflyiii/timezonehandler.dart';

final Logger log = Logger("Auth");
final Version minApiVersion = Version(6, 3, 2);
const String cfAccessClientIdHeader = "CF-Access-Client-Id";
const String cfAccessClientSecretHeader = "CF-Access-Client-Secret";

Map<String, String> cfServiceTokenHeaders(
  String? cfAccessClientId,
  String? cfAccessClientSecret,
) {
  if (cfAccessClientId == null || cfAccessClientSecret == null) {
    return <String, String>{};
  }
  return <String, String>{
    cfAccessClientIdHeader: cfAccessClientId,
    cfAccessClientSecretHeader: cfAccessClientSecret,
  };
}

String _stripWrappingQuotes(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _cleanupCfTokenValue(String value) {
  value = value.strip();
  value = _stripWrappingQuotes(value).strip();
  value = value.replaceFirst(RegExp(r'[;,]\s*$'), '');
  return value.strip();
}

String _extractCfHeaderValue(String input, String headerName) {
  final String text = input.replaceAll('\r', '').strip();
  if (text.isEmpty) {
    return "";
  }

  final String lowerHeader = headerName.toLowerCase();
  for (final String line in text.split('\n')) {
    final String trimmed = line.strip();
    if (trimmed.toLowerCase().startsWith("$lowerHeader:")) {
      final int separator = trimmed.indexOf(':');
      return _cleanupCfTokenValue(trimmed.substring(separator + 1));
    }
  }

  final RegExp inlineHeaderPattern = RegExp(
    "${RegExp.escape(headerName)}\\s*:\\s*([^\\s\"']+)",
    caseSensitive: false,
  );
  final RegExpMatch? inlineHeaderMatch = inlineHeaderPattern.firstMatch(text);
  if (inlineHeaderMatch != null) {
    return _cleanupCfTokenValue(inlineHeaderMatch.group(1)!);
  }

  return "";
}

String? _normalizeCfTokenField(String? input, String expectedHeaderName) {
  if (input == null) {
    return null;
  }
  final String strictExtraction = _extractCfHeaderValue(
    input,
    expectedHeaderName,
  );
  if (strictExtraction.isNotEmpty) {
    return strictExtraction;
  }
  final String fallback = _cleanupCfTokenValue(input);
  return fallback.isEmpty ? null : fallback;
}

class APITZReply {
  APITZReply(this.data);
  APITZReplyData data;

  factory APITZReply.fromJson(dynamic json) {
    return APITZReply(APITZReplyData.fromJson(json['data']));
  }
}

class APITZReplyData {
  APITZReplyData(this.title, this.value, this.editable);
  String title;
  String value;
  bool editable;

  factory APITZReplyData.fromJson(dynamic json) {
    return APITZReplyData(
      json['title'] as String,
      json['value'] as String,
      json['editable'] as bool,
    );
  }
}

// :TODO: translate strings. cause returns just an identifier for the translation.
class AuthError implements Exception {
  const AuthError(this.cause);

  final String cause;
}

class AuthErrorHost extends AuthError {
  const AuthErrorHost(this.host) : super("Invalid host");

  final String host;
}

class AuthErrorApiKey extends AuthError {
  const AuthErrorApiKey() : super("Invalid API key");
}

class AuthErrorVersionInvalid extends AuthError {
  const AuthErrorVersionInvalid() : super("Invalid Firefly API version");
}

class AuthErrorVersionTooLow extends AuthError {
  const AuthErrorVersionTooLow(this.requiredVersion)
    : super("Firefly API version too low");

  final Version requiredVersion;
}

class AuthErrorStatusCode extends AuthError {
  const AuthErrorStatusCode(this.code) : super("Unexpected HTTP status code");

  final int code;
}

class AuthErrorNoInstance extends AuthError {
  const AuthErrorNoInstance(this.host)
    : super("Not a valid Firefly III instance");

  final String host;
}

class AuthCredentials {
  const AuthCredentials({
    this.host,
    this.apiKey,
    this.cfAccessClientId,
    this.cfAccessClientSecret,
  });

  final String? host;
  final String? apiKey;
  final String? cfAccessClientId;
  final String? cfAccessClientSecret;
}

http.Client get httpClient => Platform.isAndroid
    ? CronetClient.fromCronetEngine(
        CronetEngine.build(
          cacheMode: CacheMode.memory,
          cacheMaxSize: 2 * 1024 * 1024,
        ),
        closeEngine: false,
      )
    : Platform.isIOS
    ? CupertinoClient.fromSessionConfiguration(
        URLSessionConfiguration.ephemeralSessionConfiguration()
          ..cache = URLCache.withCapacity(memoryCapacity: 2 * 1024 * 1024),
      )
    : http.Client();

class APIRequestInterceptor implements Interceptor {
  APIRequestInterceptor(this.headerFunc);

  final Function() headerFunc;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) {
    log.finest(() => "API query ${chain.request.method} ${chain.request.url}");
    if (chain.request.body != null) {
      log.finest(() => "Query Body: ${chain.request.body}");
    }
    final Request request = applyHeaders(
      chain.request,
      headerFunc(),
      override: true,
    );
    request.followRedirects = true;
    request.maxRedirects = 5;
    return chain.proceed(request);
  }
}

class AuthUser {
  late Uri _host;
  late String _apiKey;
  late FireflyIii _api;
  final String? _cfAccessClientId;
  final String? _cfAccessClientSecret;

  //late FireflyIiiV2 _apiV2;

  Uri get host => _host;
  FireflyIii get api => _api;

  //FireflyIiiV2 get apiV2 => _apiV2;

  final Logger log = Logger("Auth.AuthUser");

  AuthUser._create(
    Uri host,
    String apiKey, {
    String? cfAccessClientId,
    String? cfAccessClientSecret,
  }) : _cfAccessClientId = cfAccessClientId,
       _cfAccessClientSecret = cfAccessClientSecret {
    log.config("AuthUser->_create($host)");
    _apiKey = apiKey;

    _host = host.replace(pathSegments: <String>[...host.pathSegments, "api"]);

    _api = FireflyIii.create(
      baseUrl: _host,
      httpClient: httpClient,
      interceptors: <Interceptor>[APIRequestInterceptor(headers)],
    );

    /*_apiV2 = FireflyIiiV2.create(
      baseUrl: _host,
      httpClient: httpClient,
      interceptors: <Interceptor>[APIRequestInterceptor(headers)],
    );*/
  }

  Map<String, String> headers() {
    final Map<String, String> headers = <String, String>{
      HttpHeaders.authorizationHeader: "Bearer $_apiKey",
      HttpHeaders.acceptHeader: "application/json",
    };
    headers.addAll(
      cfServiceTokenHeaders(_cfAccessClientId, _cfAccessClientSecret),
    );
    return headers;
  }

  static Future<AuthUser> create(
    String host,
    String apiKey, {
    String? cfAccessClientId,
    String? cfAccessClientSecret,
  }) async {
    final Logger log = Logger("Auth.AuthUser");
    log.config("AuthUser->create($host)");

    // This call is on purpose not using the Swagger API
    final http.Client client = httpClient;
    late Uri uri;

    try {
      uri = Uri.parse(host);
    } on FormatException {
      throw AuthErrorHost(host);
    }

    final Uri aboutUri = uri.replace(
      pathSegments: <String>[...uri.pathSegments, "api", "v1", "about"],
    );

    try {
      final http.Request request = http.Request(HttpMethod.Get, aboutUri);
      request.headers[HttpHeaders.authorizationHeader] = "Bearer $apiKey";
      request.headers.addAll(
        cfServiceTokenHeaders(cfAccessClientId, cfAccessClientSecret),
      );
      // See #497, redirect is a bad way to check for (un)successful login.
      request.followRedirects = true;
      request.maxRedirects = 5;
      final http.StreamedResponse response = await client.send(request);

      // If we get an html page, it's most likely the login page, and auth failed
      if (response.headers[HttpHeaders.contentTypeHeader]?.startsWith(
            "text/html",
          ) ??
          true) {
        throw const AuthErrorApiKey();
      }
      if (response.statusCode != 200) {
        throw AuthErrorStatusCode(response.statusCode);
      }

      final String stringData = await response.stream.bytesToString();

      try {
        SystemInfo.fromJson(json.decode(stringData));
      } on FormatException {
        throw AuthErrorNoInstance(host);
      }
    } finally {
      client.close();
    }

    return AuthUser._create(
      uri,
      apiKey,
      cfAccessClientId: cfAccessClientId,
      cfAccessClientSecret: cfAccessClientSecret,
    );
  }
}

class FireflyService with ChangeNotifier {
  AuthUser? _currentUser;
  AuthUser? get user => _currentUser;
  bool _signedIn = false;
  bool get signedIn => _signedIn;
  String? _lastTriedHost;
  String? get lastTriedHost => _lastTriedHost;
  Object? _storageSignInException;
  Object? get storageSignInException => _storageSignInException;
  Version? _apiVersion;
  Version? get apiVersion => _apiVersion;

  TransStock? _transStock;
  TransStock? get transStock => _transStock;

  bool get hasApi => (_currentUser?.api != null) ? true : false;
  FireflyIii get api {
    if (_currentUser?.api == null) {
      signOut();
      throw Exception("FireflyService.api: API unavailable");
    }
    return _currentUser!.api;
  }

  /*FireflyIiiV2 get apiV2 {
    if (_currentUser?.apiV2 == null) {
      signOut();
      throw Exception("FireflyService.apiV2: API unavailable");
    }
    return _currentUser!.apiV2;
  }*/

  late CurrencyRead defaultCurrency;
  late TimeZoneHandler tzHandler;

  final FlutterSecureStorage storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  final Logger log = Logger("Auth.FireflyService");

  FireflyService() {
    log.finest(() => "new FireflyService");
  }

  Future<AuthCredentials> readStoredCredentials() async {
    return AuthCredentials(
      host: await storage.read(key: 'api_host'),
      apiKey: await storage.read(key: 'api_key'),
      cfAccessClientId: await storage.read(key: 'cf_access_client_id'),
      cfAccessClientSecret: await storage.read(key: 'cf_access_client_secret'),
    );
  }

  Future<bool> signInFromStorage() async {
    _storageSignInException = null;
    final AuthCredentials storedCredentials = await readStoredCredentials();
    final String? apiHost = storedCredentials.host;
    final String? apiKey = storedCredentials.apiKey;
    final String? cfAccessClientId = storedCredentials.cfAccessClientId;
    final String? cfAccessClientSecret = storedCredentials.cfAccessClientSecret;
    final bool cfServiceTokenSet =
        (cfAccessClientId?.isNotEmpty ?? false) &&
        (cfAccessClientSecret?.isNotEmpty ?? false);

    log.config(
      "storage: $apiHost, apiKey ${apiKey?.isEmpty ?? true ? "unset" : "set"}, "
      "cfServiceToken ${cfServiceTokenSet ? "set" : "unset"}",
    );

    if (apiHost == null || apiKey == null) {
      return false;
    }

    try {
      await signIn(
        apiHost,
        apiKey,
        cfAccessClientId: cfAccessClientId,
        cfAccessClientSecret: cfAccessClientSecret,
      );
      return true;
    } catch (e) {
      _storageSignInException = e;
      log.finest(() => "notify FireflyService->signInFromStorage");
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    log.config("FireflyService->signOut()");
    _currentUser = null;
    _signedIn = false;
    _storageSignInException = null;
    await storage.deleteAll();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    log.finest(() => "notify FireflyService->signOut");
    notifyListeners();
  }

  Future<bool> signIn(
    String host,
    String apiKey, {
    String? cfAccessClientId,
    String? cfAccessClientSecret,
  }) async {
    log.config("FireflyService->signIn($host)");
    host = host.strip().rightStrip('/');
    apiKey = apiKey.strip();
    final String rawCfAccessClientId = cfAccessClientId ?? "";
    final String rawCfAccessClientSecret = cfAccessClientSecret ?? "";

    // Allow pasting full Cloudflare header lines and extract only token values.
    cfAccessClientId = _normalizeCfTokenField(
      rawCfAccessClientId,
      cfAccessClientIdHeader,
    );
    cfAccessClientSecret = _normalizeCfTokenField(
      rawCfAccessClientSecret,
      cfAccessClientSecretHeader,
    );

    // If one field contains a full two-line Cloudflare snippet, recover both values.
    cfAccessClientId ??= _normalizeCfTokenField(
      _extractCfHeaderValue(rawCfAccessClientSecret, cfAccessClientIdHeader),
      cfAccessClientIdHeader,
    );
    cfAccessClientSecret ??= _normalizeCfTokenField(
      _extractCfHeaderValue(rawCfAccessClientId, cfAccessClientSecretHeader),
      cfAccessClientSecretHeader,
    );

    if ((cfAccessClientId == null) != (cfAccessClientSecret == null)) {
      log.warning(
        "Incomplete Cloudflare Service Token provided. "
        "Ignoring service token headers.",
      );
      cfAccessClientId = null;
      cfAccessClientSecret = null;
    }

    _lastTriedHost = host;
    final AuthUser nextUser = await AuthUser.create(
      host,
      apiKey,
      cfAccessClientId: cfAccessClientId,
      cfAccessClientSecret: cfAccessClientSecret,
    );
    final Response<CurrencySingle> currencyInfo = await nextUser.api
        .v1CurrenciesPrimaryGet();
    final CurrencyRead nextDefaultCurrency = currencyInfo.body!.data;

    final Response<SystemInfo> about = await nextUser.api.v1AboutGet();
    late Version nextApiVersion;
    try {
      String apiVersionStr = about.body?.data?.apiVersion ?? "";
      if (apiVersionStr.startsWith("develop/")) {
        apiVersionStr = "9.9.9";
      }
      nextApiVersion = Version.parse(apiVersionStr);
    } on FormatException {
      throw const AuthErrorVersionInvalid();
    }
    log.info(() => "Firefly API version $nextApiVersion");
    if (nextApiVersion < minApiVersion) {
      throw AuthErrorVersionTooLow(minApiVersion);
    }

    // Manual API query as the Swagger type doesn't resolve in Flutter :(
    final http.Client client = httpClient;
    final Uri tzUri = nextUser.host.replace(
      pathSegments: <String>[
        ...nextUser.host.pathSegments,
        "v1",
        "configuration",
        ConfigValueFilter.appTimezone.value!,
      ],
    );
    late TimeZoneHandler nextTzHandler;
    try {
      final http.Response response = await client.get(
        tzUri,
        headers: nextUser.headers(),
      );
      final APITZReply reply = APITZReply.fromJson(json.decode(response.body));
      nextTzHandler = TimeZoneHandler(reply.data.value);
    } finally {
      client.close();
    }

    _currentUser = nextUser;
    defaultCurrency = nextDefaultCurrency;
    _apiVersion = nextApiVersion;
    tzHandler = nextTzHandler;
    _signedIn = true;
    _transStock = TransStock(nextUser.api);
    log.finest(() => "notify FireflyService->signIn");
    notifyListeners();

    await storage.write(key: 'api_host', value: host);
    await storage.write(key: 'api_key', value: apiKey);
    if (cfAccessClientId != null && cfAccessClientSecret != null) {
      await storage.write(key: 'cf_access_client_id', value: cfAccessClientId);
      await storage.write(
        key: 'cf_access_client_secret',
        value: cfAccessClientSecret,
      );
    } else {
      await storage.delete(key: 'cf_access_client_id');
      await storage.delete(key: 'cf_access_client_secret');
    }

    return true;
  }
}

void apiThrowErrorIfEmpty(Response<dynamic> response, BuildContext? context) {
  if (response.isSuccessful && response.body != null) {
    return;
  }
  log.severe("Invalid API response", response.error);
  if (context?.mounted ?? false) {
    throw Exception(
      S.of(context!).errorAPIInvalidResponse(response.error?.toString() ?? ""),
    );
  } else {
    throw Exception("[nocontext] Invalid API response: ${response.error}");
  }
}
