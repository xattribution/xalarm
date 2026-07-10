/// Build metadata baked in at compile time (see Dockerfile --dart-define).
/// 'dev' / 'unknown' when running from an IDE.
class BuildInfo {
  const BuildInfo._();

  /// Keep in sync with pubspec.yaml's `version`.
  static const String version = '1.5.0';

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
