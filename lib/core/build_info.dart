import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Build metadata: the real versionName/versionCode from the installed
/// package, plus commit/date baked in at compile time (see Dockerfile
/// --dart-define). 'dev' / 'unknown' when running from an IDE.
class BuildInfo {
  const BuildInfo._();

  static String _version = 'dev';
  static String _buildNumber = '';

  /// e.g. `1.6.0`. Populated by [load]; `dev` until then or off-device.
  static String get version => _version;
  static String get buildNumber => _buildNumber;

  /// Reads the package's version once at startup. Safe to call anywhere;
  /// platforms without the plugin (tests) keep the defaults.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
    } catch (e) {
      debugPrint('BuildInfo: package info unavailable: $e');
    }
  }

  /// True in Play Store builds (--dart-define=PLAY_STORE=true). Play policy
  /// forbids apps installing their own APKs, so the self-update flow is
  /// compiled out and Google Play owns updates.
  static const bool isPlayStore = bool.fromEnvironment(
    'PLAY_STORE',
    defaultValue: false,
  );

  static const String commit = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: 'dev',
  );

  static const String date = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: 'unknown',
  );
}
