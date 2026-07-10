import 'package:flutter/material.dart';

/// The xalarm palette: black · blue · tan · white. Flat and calm — no neon,
/// no gradients, no glow. Two tuned sets for dark (default) and light.
class AppColors {
  const AppColors._();

  // Shared accents.
  static const blue = Color(0xFF3B6FE0); // calm, not neon
  static const blueLight = Color(0xFF2F63D6); // slightly deeper on white
  static const tan = Color(0xFFCBAE86); // sand / warm neutral
  static const tanDeep = Color(0xFFB7975F);
  static const danger = Color(0xFFE5484D);

  // Dark scheme.
  static const darkBg = Color(0xFF0E1116); // near-black
  static const darkSurface = Color(0xFF171A1F);
  static const darkSurfaceHi = Color(0xFF1E232B);
  static const darkText = Color(0xFFF2F4F7);
  static const darkTextMuted = Color(0xFF9AA4B2);
  static const darkDivider = Color(0xFF262B33);

  // Light scheme.
  static const lightBg = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF4F5F7);
  static const lightSurfaceHi = Color(0xFFECEEF1);
  static const lightText = Color(0xFF12151A);
  static const lightTextMuted = Color(0xFF5B6472);
  static const lightDivider = Color(0xFFE3E6EA);
}
