import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Flat Material 3 themes for xalarm. Clean clock aesthetic: minimal elevation,
/// no surface tint, tabular figures for every numeric display.
class AppTheme {
  const AppTheme._();

  /// Tabular figures so clock digits never shift width as they tick.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: AppColors.blue,
      onPrimary: Colors.white,
      secondary: AppColors.tan,
      onSecondary: Color(0xFF1A1206),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      surfaceContainerHighest: AppColors.darkSurfaceHi,
      error: AppColors.danger,
      outlineVariant: AppColors.darkDivider,
    ),
    bg: AppColors.darkBg,
    muted: AppColors.darkTextMuted,
    systemOverlay: SystemUiOverlayStyle.light,
  );

  static ThemeData light() => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: AppColors.blueLight,
      onPrimary: Colors.white,
      secondary: AppColors.tanDeep,
      onSecondary: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightText,
      surfaceContainerHighest: AppColors.lightSurfaceHi,
      error: AppColors.danger,
      outlineVariant: AppColors.lightDivider,
    ),
    bg: AppColors.lightBg,
    muted: AppColors.lightTextMuted,
    systemOverlay: SystemUiOverlayStyle.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color bg,
    required Color muted,
    required SystemUiOverlayStyle systemOverlay,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
    );

    TextStyle tab(TextStyle? s) => (s ?? const TextStyle()).copyWith(
      fontFeatures: _tabular,
    );

    return base.copyWith(
      canvasColor: bg,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemOverlay,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : muted,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(iconColor: muted),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: tab(base.textTheme.displayLarge).copyWith(
          fontWeight: FontWeight.w300,
        ),
        displayMedium: tab(base.textTheme.displayMedium).copyWith(
          fontWeight: FontWeight.w300,
        ),
        headlineLarge: tab(base.textTheme.headlineLarge),
        headlineMedium: tab(base.textTheme.headlineMedium),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      extensions: [AppTextColors(muted: muted)],
    );
  }
}

/// Muted text color exposed as a theme extension so widgets can read it
/// without hard-coding light/dark values.
class AppTextColors extends ThemeExtension<AppTextColors> {
  final Color muted;
  const AppTextColors({required this.muted});

  @override
  AppTextColors copyWith({Color? muted}) =>
      AppTextColors(muted: muted ?? this.muted);

  @override
  AppTextColors lerp(ThemeExtension<AppTextColors>? other, double t) {
    if (other is! AppTextColors) return this;
    return AppTextColors(muted: Color.lerp(muted, other.muted, t) ?? muted);
  }
}

/// Convenience accessor for the muted text color.
extension AppThemeContext on BuildContext {
  Color get mutedColor =>
      Theme.of(this).extension<AppTextColors>()?.muted ??
      Theme.of(this).colorScheme.onSurface;
}
