import 'package:flutter/material.dart';

/// App-wide user settings, persisted as JSON.
class AppSettings {
  final ThemeMode themeMode;

  /// Local-network REST API (Home Assistant integration).
  final bool apiEnabled;
  final int apiPort;
  final String apiToken;

  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.apiEnabled = false,
    this.apiPort = 8787,
    this.apiToken = '',
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? apiEnabled,
    int? apiPort,
    String? apiToken,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    apiEnabled: apiEnabled ?? this.apiEnabled,
    apiPort: apiPort ?? this.apiPort,
    apiToken: apiToken ?? this.apiToken,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'apiEnabled': apiEnabled,
    'apiPort': apiPort,
    'apiToken': apiToken,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ??
        ThemeMode.dark,
    apiEnabled: json['apiEnabled'] as bool? ?? false,
    apiPort: json['apiPort'] as int? ?? 8787,
    apiToken: json['apiToken'] as String? ?? '',
  );
}
