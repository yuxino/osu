import 'package:flutter/material.dart';

abstract final class AppColors {
  static const cream = Color(0xFFF5F1E8);
  static const warmWhite = Color(0xFFFFFDF7);
  static const ink = Color(0xFF17352F);
  static const mutedInk = Color(0xFF64716D);
  static const coral = Color(0xFFF2695C);
  static const coralDark = Color(0xFFDA5147);
  static const lime = Color(0xFFD7F06B);
  static const sky = Color(0xFFAFD9E5);
  static const darkPaper = Color(0xFF10241F);
  static const darkCard = Color(0xFF17342D);
}

abstract final class AppTheme {
  static ThemeData get light => _build(
    brightness: Brightness.light,
    scaffold: AppColors.cream,
    surface: AppColors.warmWhite,
    text: AppColors.ink,
    muted: AppColors.mutedInk,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    scaffold: AppColors.darkPaper,
    surface: AppColors.darkCard,
    text: AppColors.cream,
    muted: const Color(0xFFADBBB6),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
    required Color text,
    required Color muted,
  }) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.coral,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: AppColors.coral,
          secondary: AppColors.lime,
          tertiary: AppColors.sky,
          onSurface: text,
          outline: muted.withValues(alpha: 0.45),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: 'Manrope',
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: 88,
          height: 0.88,
          fontWeight: FontWeight.w700,
          letterSpacing: -4.5,
          color: text,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: 54,
          height: 0.95,
          fontWeight: FontWeight.w600,
          letterSpacing: -2.5,
          color: text,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
          color: text,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.7, color: muted),
        bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: muted),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: text,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
