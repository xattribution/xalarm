import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/json_file.dart';
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

  Future<void> setUpdateUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _update(
      (state.value ?? const AppSettings())
          .copyWith(updateUrl: trimmed.isEmpty ? kDefaultUpdateUrl : trimmed),
    );
  }

  static String _newToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
