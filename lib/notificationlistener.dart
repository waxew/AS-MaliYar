import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:notifications_listener_service/notifications_listener_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:waterflyiii/app.dart';
import 'package:waterflyiii/auth.dart';
import 'package:waterflyiii/generated/swagger_fireflyiii_api/firefly_iii.swagger.dart';
import 'package:waterflyiii/pages/transaction.dart';
import 'package:waterflyiii/settings.dart';

final Logger log = Logger("NotificationListener");

class NotificationTransaction {
  NotificationTransaction(this.appName, this.title, this.body, this.date);

  final String appName;
  final String title;
  final String body;
  final DateTime date;

  NotificationTransaction.fromJson(Map<String, dynamic> json)
    : appName = json['appName'],
      title = json['title'],
      body = json['body'],
      date = DateTime.parse(json['date']);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'appName': appName,
    'title': title,
    'body': body,
    'date': date.toIso8601String(),
  };
}

class NotificationListenerStatus {
  NotificationListenerStatus(
    this.servicePermission,
    this.serviceRunning,
    this.notificationPermission,
  );

  final bool servicePermission;
  final bool serviceRunning;
  final bool notificationPermission;
}

final RegExp rFindMoney = RegExp(
  r'(?:^|[^\w])(?<preCurrency>(?:[^\r\n\t\f\v 0-9]){0,3})\s*(?<amount>\d[.,\s\d]+(?:[.,]\d+)?)\s*(?<postCurrency>(?:[^\r\n\t\f\v 0-9]){0,3})(?:$|\s|\.|,)',
);

Future<NotificationListenerStatus> nlStatus() async {
  if (Platform.isAndroid) {
    return NotificationListenerStatus(
      await NotificationServicePlugin.instance.isServicePermissionGranted(),
      await NotificationServicePlugin.instance.isServiceRunning(),
      await FlutterLocalNotificationsPlugin()
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()!
              .areNotificationsEnabled() ??
          false,
    );
  } else {
    return NotificationListenerStatus(false, false, false);
  }
}

@pragma('vm:entry-point')
void nlCallback() {
  if (!Platform.isAndroid) {
    return;
  }
  log.finest(() => "nlCallback()");
  NotificationServicePlugin.instance.executeNotificationListener((
    NotificationEvent? evt,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (evt == null || evt.packageName == null) {
      return;
    }
    if ((evt.packageName?.startsWith("com.dreautall.waterflyiii") ?? false) ||
        (evt.packageName?.startsWith("com.waterflyiii.test") ?? false)) {
      return;
    }
    // if (evt.state == NotificationState.remove) {
    if (evt.state != NotificationState.post) {
      return;
    }

    // Passed initial checks
    final SettingsProvider settings = SettingsProvider();
    final PastNotification notif = PastNotification(
      evt.packageName!,
      evt.title ?? "",
      evt.text ?? "",
      DateTime.now(),
      null,
    );

    bool isPotentialMatch = false;
    if (evt.text?.contains(RegExp(r'\d')) ?? false) {
      unawaited(settings.notificationAddKnownApp(evt.packageName!));
    } else {
      notif.reason = PastNotificationMissedReasons.noMoney;
      await settings.notificationHistoryAdd(notif);
      log.finer(() => "nlCallback(${evt.packageName}): no money found");
      return;
    }

    final NotificationAppSettings appSettings = await settings
        .notificationGetAppSettings(evt.packageName!);

    if (appSettings.regex != null && appSettings.regex!.isNotEmpty) {
      isPotentialMatch = RegExp(appSettings.regex!).hasMatch(text);
    } else {
      final Iterable<RegExpMatch> matches = rFindMoney.allMatches(text);
      for (RegExpMatch match in matches) {
        if ((match.namedGroup("postCurrency")?.isNotEmpty ?? false) ||
            (match.namedGroup("preCurrency")?.isNotEmpty ?? false)) {
          isPotentialMatch = true;
          break;
        }
      }
    }

    if (!isPotentialMatch) {
      notif.reason = PastNotificationMissedReasons.noCurrency; // :TODO: noMatch
      await settings.notificationHistoryAdd(notif);
      log.finer(
        () => "nlCallback(${evt.packageName}): no match found",
      );
      return;
    }

    // Valid notification
    await settings.notificationAddKnownApp(evt.packageName!);

    if (!(await settings.notificationUsedApps()).contains(evt.packageName)) {
      notif.reason = PastNotificationMissedReasons.appNotUsed;
      await settings.notificationHistoryAdd(notif);
      log.finer(() => "nlCallback(${evt.packageName}): app not used");
      return;
    }

    // Passed, add tx/show add notification
    await settings.notificationHistoryAdd(notif);
    bool showNotification = true;

    tz.initializeTimeZones();
    try {
      final FireflyService ffService = FireflyService();
      if (!await ffService.signInFromStorage()) {
        throw UnauthenticatedResponse;
      }
      final FireflyIii api = ffService.api;
      final CurrencyRead localCurrency = ffService.defaultCurrency;
      late CurrencyRead? currency;
      late double amount;

      (currency, amount) = await parseNotificationText(
        api,
        evt.text ?? "",
        localCurrency,
        userRegex: appSettings.regex,
      );

      if (amount <= 0) {
        log.finer(() => "nlCallback(${evt.packageName}): amount is 0");
        return;
      }

      if (appSettings.autoAdd) {
        log.finer(
          () =>
              "nlCallback(${evt.packageName}): trying to auto-add transaction",
        );
        // Set date
        final DateTime date = ffService.tzHandler
            .notificationTXTime(
              DateTime.tryParse(evt.postTime ?? "") ?? DateTime.now(),
            )
            .toLocal();
        String note = evt.text ?? "";

        // Check currency
        if (currency?.id != localCurrency.id) {
          throw Exception("Can't auto-add TX with foreign currency");
        }

        // Check account
        if (appSettings.defaultAccountId == null) {
          throw Exception("Can't auto-add TX with no default account ID");
        }

        final TransactionStore newTx = TransactionStore(
          groupTitle: null,
          transactions: <TransactionSplitStore>[
            TransactionSplitStore(
              type: .withdrawal,
              date: date,
              amount: amount.toString(),
              description: evt.title ?? "Notification Transaction",
              notes: note,
              order: 0,
              sourceId: appSettings.defaultAccountId,
            ),
          ],
          applyRules: true,
          fireWebhooks: true,
          errorIfDuplicateHash: true,
        );
        final Response<TransactionSingle> resp = await api.v1TransactionsPost(
          body: newTx,
        );
        if (!resp.isSuccessful || resp.body == null) {
          try {
            final ValidationErrorResponse valError = .fromJson(
              json.decode(resp.error.toString()),
            );
            throw Exception("nlCallBack PostTransaction: ${valError.message}");
          } catch (_) {
            throw Exception("nlCallBack PostTransaction: unknown");
          }
        }

        unawaited(
          FlutterLocalNotificationsPlugin().show(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: "Transaction created",
            body: "Transaction created based on notification ${evt.title}",
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'extract_transaction_created',
                'Transaction from Notification Created',
                channelDescription:
                    'Notification that a Transaction has been created from another Notification.',
                importance: .low, // Android 8.0 and higher
                priority: .low, // Android 7.1 and lower
              ),
            ),
            payload: "",
          ),
        );

        showNotification = false;
      }
    } catch (e, stackTrace) {
      log.severe("Error while processing notification", e, stackTrace);
      showNotification = true;
    }

    if (showNotification) {
      // :TODO: l10n
      unawaited(
        FlutterLocalNotificationsPlugin().show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: "Create Transaction?",
          // :TODO: once we l10n this, a better switch can be implemented...
          body:
              "Click to create a transaction based on the notification ${evt.title ?? evt.packageName ?? ""}",
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'extract_transaction',
              'Create Transaction from Notification',
              channelDescription:
                  'Notification asking to create a transaction from another Notification.',
              importance: .low, // Android 8.0 and higher
              priority: .low, // Android 7.1 and lower
            ),
          ),
          payload: jsonEncode(
            NotificationTransaction(
              evt.packageName ?? "",
              evt.title ?? "",
              text,
              DateTime.tryParse(evt.postTime ?? "") ?? DateTime.now(),
            ),
          ),
        ),
      );
    }
  });
}

Future<void> nlInit() async {
  if (!Platform.isAndroid) {
    return;
  }
  log.finest(() => "nlInit()");
  await NotificationServicePlugin.instance.initialize(nlCallback);
  // nlCallback(); // Avoid duplicated notification.
}

Future<void> nlNotificationTap(
  NotificationResponse notificationResponse,
) async {
  log.finest(() => "nlNotificationTap()");
  if (notificationResponse.payload?.isEmpty ?? true) {
    return;
  }
  await showDialog(
    context: navigatorKey.currentState!.context,
    builder: (BuildContext context) => TransactionPage(
      notification: .fromJson(jsonDecode(notificationResponse.payload!)),
    ),
  );
}

Future<(CurrencyRead?, double)> parseNotificationText(
  FireflyIii api,
  String notificationBody,
  CurrencyRead localCurrency, {
  String? userRegex,
}) async {
  CurrencyRead? currency;
  double amount = 0;
  String? extractedAmountStr;

  // Prioritizes userRegex
  if (userRegex != null && userRegex.isNotEmpty) {
    final RegExp reg = RegExp(userRegex);
    final RegExpMatch? match = reg.firstMatch(notificationBody);
    if (match != null) {
      extractedAmountStr = match.namedGroup("amount");
      if (extractedAmountStr == null && match.groupCount > 0) {
        extractedAmountStr = match.group(1);
      }
    }
  } else {
    // Fallback to legacy
    final Iterable<RegExpMatch> matches = rFindMoney.allMatches(
      notificationBody,
    );

    if (matches.isNotEmpty) {
      final List<CurrencyRead> currencies =
          (await api.v1CurrenciesGet()).body!.data;
      currencies.removeWhere((c) => c.attributes.enabled != true);
      currencies.add(localCurrency);

      int bestMatchIndex = -1;
      for (int i = 0; i < matches.length; ++i) {
        final RegExpMatch match = matches.elementAt(i);
        final String pre = match.namedGroup("preCurrency") ?? "";
        final String post = match.namedGroup("postCurrency") ?? "";

        if (pre.isNotEmpty || post.isNotEmpty) {
          if (bestMatchIndex == -1) bestMatchIndex = i;
          for (CurrencyRead apiCurrency in currencies) {
            if (apiCurrency.attributes.code == pre ||
                apiCurrency.attributes.symbol == pre ||
                apiCurrency.attributes.code == post ||
                apiCurrency.attributes.symbol == post) {
              bestMatchIndex = i;
              currency = apiCurrency;
              break;
            }
          }
          if (currency != null) break;
        }
      }
      if (bestMatchIndex != -1) {
        extractedAmountStr = matches
            .elementAt(bestMatchIndex)
            .namedGroup("amount");
      }
    }
  }

  String? cleanAmount;
  if (extractedAmountStr != null) {
    cleanAmount = extractedAmountStr.replaceAll(RegExp(r'[^0-9.,]'), '');

    if (cleanAmount.isNotEmpty) {
      cleanAmount = cleanAmount.replaceAll(',', '.');

      if ('.'.allMatches(cleanAmount).length > 1) {
        int lastDotIndex = cleanAmount.lastIndexOf('.');
        String beforeDot = cleanAmount
            .substring(0, lastDotIndex)
            .replaceAll('.', '');
        String afterDot = cleanAmount.substring(lastDotIndex + 1);
        cleanAmount = '$beforeDot.$afterDot';
    }
      amount = double.tryParse(cleanAmount) ?? 0.0;
  }

  return (currency ?? localCurrency, amount);
}
