import 'package:flutter/material.dart';

/// Where the self-hosted download site lives; the app checks
/// `<updateUrl>/version.json` for newer builds and downloads
/// `<updateUrl>/xalarm.apk`.
const String kDefaultUpdateUrl = 'https://xalarm.tinbadger.com';

/// App-wide user settings, persisted as JSON.
class AppSettings {
  final ThemeMode themeMode;

  /// Local-network REST API (Home Assistant integration).
  final bool apiEnabled;
  final int apiPort;
  final String apiToken;

  /// Base URL of the self-hosted download site used for update checks.
  final String updateUrl;

  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.apiEnabled = false,
    this.apiPort = 8787,
    this.apiToken = '',
    this.updateUrl = kDefaultUpdateUrl,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? apiEnabled,
    int? apiPort,
    String? apiToken,
    String? updateUrl,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    apiEnabled: apiEnabled ?? this.apiEnabled,
    apiPort: apiPort ?? this.apiPort,
    apiToken: apiToken ?? this.apiToken,
    updateUrl: updateUrl ?? this.updateUrl,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'apiEnabled': apiEnabled,
    'apiPort': apiPort,
    'apiToken': apiToken,
    'updateUrl': updateUrl,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ??
        ThemeMode.dark,
    apiEnabled: json['apiEnabled'] as bool? ?? false,
    apiPort: json['apiPort'] as int? ?? 8787,
    apiToken: json['apiToken'] as String? ?? '',
    updateUrl: json['updateUrl'] as String? ?? kDefaultUpdateUrl,
  );
}
