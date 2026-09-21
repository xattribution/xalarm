import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/json_file.dart';
import '../net/url_policy.dart';
import 'app_settings.dart';

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  final _file = JsonFile('settings.json');

  @override
  Future<AppSettings> build() async {
    final raw = await _file.read();
    var settings = raw is Map
        ? AppSettings.fromJson(Map<String, dynamic>.from(raw))
        : const AppSettings();
    // Generate the API token once, up front, so it's ready to copy the
    // moment the user opens settings.
    if (settings.apiToken.isEmpty) {
      settings = settings.copyWith(apiToken: _newToken());
      await _file.write(settings.toJson());
    }
    return settings;
  }

  Future<void> _update(AppSettings next) async {
    state = AsyncData(next);
    await _file.write(next.toJson());
  }

  Future<void> setThemeMode(ThemeMode mode) async =>
      _update((state.value ?? const AppSettings()).copyWith(themeMode: mode));

  Future<void> setApiEnabled(bool enabled) async =>
      _update((state.value ?? const AppSettings()).copyWith(apiEnabled: enabled));

  Future<void> setApiPort(int port) async => _update(
    (state.value ?? const AppSettings())
        .copyWith(apiPort: port.clamp(1024, 65535)),
  );

  Future<void> regenerateToken() async =>
      _update((state.value ?? const AppSettings()).copyWith(apiToken: _newToken()));

  /// Empty resets to the default. Returns a reason when [url] is refused
  /// (wrong scheme, or cleartext to a non-local host); the setting is then
  /// left unchanged.
  Future<String?> setSyncUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty) {
      final problem = UrlPolicy.checkWebSocket(trimmed);
      if (problem != null) return problem;
    }
    await _update(
      (state.value ?? const AppSettings())
          .copyWith(syncUrl: trimmed.isEmpty ? kDefaultSyncUrl : trimmed),
    );
    return null;
  }

  Future<String?> setUpdateUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isNotEmpty) {
      final problem = UrlPolicy.checkHttp(trimmed);
      if (problem != null) return problem;
    }
    await _update(
      (state.value ?? const AppSettings())
          .copyWith(updateUrl: trimmed.isEmpty ? kDefaultUpdateUrl : trimmed),
    );
    return null;
  }

  static String _newToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
