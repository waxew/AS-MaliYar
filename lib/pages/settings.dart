// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:animations/animations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show CorePalette;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:waterflyiii/auth.dart';
import 'package:waterflyiii/extensions.dart';
import 'package:waterflyiii/generated/l10n/app_localizations.dart';
import 'package:waterflyiii/notificationlistener.dart';
import 'package:waterflyiii/pages/settings/debug.dart';
import 'package:waterflyiii/pages/settings/notifications.dart';
import 'package:waterflyiii/settings.dart';

final Logger log = Logger("Pages.Settings");

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  final Logger log = Logger("Pages.Settings.Page");

  @override
  Widget build(BuildContext context) {
    log.finest(() => "build()");

    final SettingsProvider settings = context.read<SettingsProvider>();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      primary: false,
      children: <Widget>[
        ListTile(
          title: Text(S.of(context).settingsLanguage),
          subtitle: Text(S.of(context).localeName),
          leading: const CircleAvatar(child: Icon(Icons.language)),
          onTap: () {
            showDialog<Locale?>(
              context: context,
              builder: (BuildContext context) => const LanguageDialog(),
            ).then((Locale? locale) async {
              if (locale == null) {
                return;
              }
              await settings.setLocale(locale);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                const QuickActions().setShortcutItems(<ShortcutItem>[
                  ShortcutItem(
                    type: "action_transaction_add",
                    localizedTitle: S.of(context).transactionTitleAdd,
                    icon: "action_icon_add",
                  ),
                ]);
              });
            });
          },
        ),
        FutureBuilder<CorePalette?>(
          future: DynamicColorPlugin.getCorePalette(),
          builder: (BuildContext context, AsyncSnapshot<CorePalette?> snapshot) {
            String dynamicColor = "";
            bool dynamicColorAvailable = false;
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                snapshot.data != null) {
              // Dynamic color support available
              dynamicColorAvailable = true;
              if (context.select((SettingsProvider s) => s.dynamicColors)) {
                dynamicColor = " - ${S.of(context).settingsThemeDynamicColors}";
              }
            }
            return ListTile(
              title: Text(S.of(context).settingsTheme),
              subtitle: Text(
                "${S.of(context).settingsThemeValue(context.select((SettingsProvider s) => s.theme).toString().split('.').last)}$dynamicColor",
              ),
              leading: const CircleAvatar(child: Icon(Icons.format_paint)),
              onTap: () {
                showDialog<ThemeMode?>(
                  context: context,
                  builder: (BuildContext context) =>
                      ThemeDialog(dynamicColorAvailable: dynamicColorAvailable),
                ).then((ThemeMode? theme) {
                  if (theme == null) {
                    return;
                  }
                  settings.setTheme(theme);
                });
              },
            );
          },
        ),
        SwitchListTile.adaptive(
          title: Text(S.of(context).settingsUseServerTimezone),
          subtitle: Text(S.of(context).settingsUseServerTimezoneHelp),
          value: context.select((SettingsProvider s) => s.useServerTime),
          secondary: CircleAvatar(
            child: Icon(
              context.select((SettingsProvider s) => s.useServerTime)
                  ? Icons.schedule
                  : Icons.schedule_outlined,
            ),
          ),
          onChanged: (bool value) async {
            await context.read<FireflyService>().tzHandler.setUseServerTime(
              value,
            );
            settings.useServerTime = value;
          },
        ),
        ListTile(
          title: const Text("Server connection"),
          subtitle: Text(
            context.select((FireflyService f) {
              final Uri? host = f.user?.host;
              if (host == null) {
                return "-";
              }
              final List<String> segments = <String>[...host.pathSegments];
              if (segments.isNotEmpty && segments.last == "api") {
                segments.removeLast();
              }
              return host.replace(pathSegments: segments).toString();
            }),
            maxLines: 2,
          ),
          leading: const CircleAvatar(child: Icon(Icons.cloud_outlined)),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (BuildContext context) => const ConnectionDialog(),
            );
          },
        ),
        const Divider(),
        SwitchListTile.adaptive(
          title: Text(S.of(context).settingsLockscreen),
          subtitle: Text(S.of(context).settingsLockscreenHelp),
          value: context.select((SettingsProvider s) => s.lock),
          secondary: CircleAvatar(
            child: Icon(
              context.select((SettingsProvider s) => s.lock)
                  ? Icons.lock
                  : Icons.lock_outline,
            ),
          ),
          onChanged: (bool value) async {
            final S l10n = S.of(context);
            final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
            if (value == true) {
              final LocalAuthentication auth = LocalAuthentication();
              final bool canAuth =
                  await auth.isDeviceSupported() ||
                  await auth.canCheckBiometrics;
              if (!canAuth) {
                log.warning("no auth method supported");
                return;
              }
              log.finest("trying authentication");
              late bool authed;
              try {
                authed = await auth.authenticate(
                  localizedReason: l10n.settingsLockscreenInitial,
                );
              } catch (e, stackTrace) {
                log.severe("auth failed", e, stackTrace);
                msg.showSnackBar(
                  SnackBar(
                    content: Text(l10n.errorUnknown),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              if (!authed) {
                log.warning("authentication was cancelled");
                return;
              }
            }
            settings.lock = value;
          },
        ),
        const Divider(),
        if (Platform.isAndroid)
          FutureBuilder<NotificationListenerStatus>(
            future: nlStatus(),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<NotificationListenerStatus> snapshot,
                ) {
                  final S l10n = S.of(context);

                  late String subtitle;
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    if (!snapshot.data!.servicePermission ||
                        !snapshot.data!.notificationPermission) {
                      subtitle = l10n.settingsNLPermissionNotGranted;
                    } else if (!snapshot.data!.serviceRunning) {
                      subtitle = l10n.settingsNLServiceStopped;
                    } else {
                      subtitle = l10n.settingsNLServiceRunning;
                    }
                  } else if (snapshot.hasError) {
                    log.severe(
                      "error getting nlStatus",
                      snapshot.error,
                      snapshot.stackTrace,
                    );
                    subtitle = S
                        .of(context)
                        .settingsNLServiceCheckingError(
                          snapshot.error.toString(),
                        );
                  } else {
                    subtitle = S.of(context).settingsNLServiceChecking;
                  }
                  return OpenContainer(
                    openBuilder:
                        (BuildContext context, Function closedContainer) =>
                            const SettingsNotifications(),
                    openColor: Theme.of(context).cardColor,
                    closedColor: Theme.of(context).cardColor,
                    closedElevation: 0,
                    closedBuilder:
                        (BuildContext context, Function openContainer) =>
                            ListTile(
                              title: Text(
                                S.of(context).settingsNotificationListener,
                              ),
                              subtitle: Text(subtitle, maxLines: 2),
                              leading: const CircleAvatar(
                                child: Icon(Icons.notifications),
                              ),
                              onTap: () => openContainer(),
                            ),
                    onClosed: (_) => setState(() {}),
                  );
                },
          ),
        if (Platform.isAndroid) const Divider(),
        ListTile(
          title: Text(S.of(context).settingsFAQ),
          subtitle: Text(S.of(context).settingsFAQHelp),
          leading: const CircleAvatar(child: Icon(Icons.question_answer)),
          onTap: () async {
            final Uri uri = Uri.parse(
              "https://github.com/dreautall/waterfly-iii/blob/master/FAQ.md",
            );
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              throw Exception("Could not open URL");
            }
          },
        ),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
            return ListTile(
              title: Text(S.of(context).settingsVersion),
              subtitle: Text(
                (snapshot.data != null)
                    ? "${snapshot.data!.appName}, ${snapshot.data!.version}+${snapshot.data!.buildNumber}"
                    : S.of(context).settingsVersionChecking,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.info_outline_rounded),
              ),
              onTap: () => showDialog(
                context: context,
                builder: (BuildContext context) => const DebugDialog(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class LanguageDialog extends StatelessWidget {
  const LanguageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("current locale: ${S.of(context).localeName}");
    return SimpleDialog(
      title: Text(S.of(context).settingsDialogLanguageTitle),
      children: <Widget>[
        RadioGroup<Locale>(
          groupValue: LocaleExt.fromLanguageTag(S.of(context).localeName),
          onChanged: (Locale? locale) {
            Navigator.pop(context, locale);
          },
          child: Column(
            children: <Widget>[
              ...S.supportedLocales.map(
                (Locale locale) => RadioListTile<Locale>.adaptive(
                  value: locale,
                  title: Text(locale.toLanguageTag()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ThemeDialog extends StatelessWidget {
  const ThemeDialog({super.key, required this.dynamicColorAvailable});

  final bool dynamicColorAvailable;

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.read<SettingsProvider>();
    return SimpleDialog(
      title: Text(S.of(context).settingsDialogThemeTitle),
      children: <Widget>[
        dynamicColorAvailable
            ? SwitchListTile.adaptive(
                title: Text(S.of(context).settingsThemeDynamicColors),
                value: context.select((SettingsProvider s) => s.dynamicColors),
                isThreeLine: false,
                onChanged: (bool value) => settings.dynamicColors = value,
              )
            : const SizedBox.shrink(),
        RadioGroup<ThemeMode>(
          groupValue: settings.theme,
          onChanged: (ThemeMode? theme) {
            Navigator.pop(context, theme);
          },
          child: Column(
            children: <Widget>[
              ...ThemeMode.values.map(
                (ThemeMode theme) => RadioListTile<ThemeMode>.adaptive(
                  value: theme,
                  title: Text(
                    S
                        .of(context)
                        .settingsThemeValue(theme.toString().split('.').last),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final TextEditingController _hostTextController = TextEditingController();
  final TextEditingController _keyTextController = TextEditingController();
  final TextEditingController _customHeadersTextController =
      TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _showCustomHeadersField = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _hostTextController.dispose();
    _keyTextController.dispose();
    _customHeadersTextController.dispose();
    super.dispose();
  }

  static bool _hostValid(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    return uri.scheme == "https" || uri.scheme == "http";
  }

  Future<void> _loadCredentials() async {
    final FireflyService ff = context.read<FireflyService>();
    final AuthCredentials creds = await ff.readStoredCredentials();
    final Uri? currentHost = ff.user?.host;

    String host = creds.host ?? "";
    if (host.isEmpty && currentHost != null) {
      final List<String> segments = <String>[...currentHost.pathSegments];
      if (segments.isNotEmpty && segments.last == "api") {
        segments.removeLast();
      }
      host = currentHost.replace(pathSegments: segments).toString();
    }
    if (host.isEmpty) {
      host = "https://";
    }

    if (!mounted) {
      return;
    }

    _hostTextController.text = host;
    _keyTextController.text = creds.apiKey ?? "";
    _customHeadersTextController.text = creds.customHeadersRaw ?? "";

    setState(() {
      _showCustomHeadersField = _customHeadersTextController.text.isNotEmpty;
      _loading = false;
    });
  }

  String _errorDescription(Object error, BuildContext context) {
    if (error is AuthErrorStatusCode) {
      return "${error.cause}\n${S.of(context).errorStatusCode(error.code)}";
    }
    if (error is AuthErrorVersionTooLow) {
      return "${error.cause}\n${S.of(context).errorMinAPIVersion(error.requiredVersion.toString())}";
    }
    if (error is AuthError) {
      return error.cause;
    }
    return S.of(context).errorUnknown;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _submitError = null;
    });

    try {
      await context.read<FireflyService>().signIn(
        _hostTextController.text,
        _keyTextController.text,
        customHeadersRaw: _customHeadersTextController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Connection settings updated."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      log.warning("failed to update server credentials", error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = _errorDescription(error, context);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Server connection"),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _loading
            ? const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: _hostTextController,
                        decoration: InputDecoration(
                          filled: true,
                          labelText: S.of(context).loginFormLabelHost,
                        ),
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return S.of(context).errorFieldRequired;
                          }
                          if (!_hostValid(value)) {
                            return S.of(context).errorInvalidURL;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _keyTextController,
                        decoration: InputDecoration(
                          filled: true,
                          labelText: S.of(context).loginFormLabelAPIKey,
                        ),
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return S.of(context).errorFieldRequired;
                          }
                          return null;
                        },
                      ),
                      if (_showCustomHeadersField) ...<Widget>[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customHeadersTextController,
                          decoration: const InputDecoration(
                            filled: true,
                            labelText: "Custom headers (optional)",
                            helperText: "One per line: Header-Name: value",
                          ),
                          minLines: 3,
                          maxLines: 8,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                      ],
                      if (_submitError != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _submitError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        OutlinedButton(
          onPressed: _loading || _saving
              ? null
              : () {
                  setState(() {
                    _showCustomHeadersField = !_showCustomHeadersField;
                  });
                },
          child: Text(_showCustomHeadersField ? "Hide headers" : "Headers"),
        ),
        FilledButton(
          onPressed: _loading || _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Save"),
        ),
      ],
    );
  }
}
