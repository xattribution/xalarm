/// Build metadata baked in at compile time (see Dockerfile --dart-define).
/// 'dev' / 'unknown' when running from an IDE.
class BuildInfo {
  const BuildInfo._();

  static const String commit = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: 'dev',
  );

  static const String date = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: 'unknown',
  );
}
