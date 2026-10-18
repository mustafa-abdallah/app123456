import 'package:flutter/material.dart';

const kAmber = Color(0xFFFFB02E);
const kTeal = Color(0xFF5CCFC0);
const _darkBg = Color(0xFF1B1D2A);
const _darkSurface = Color(0xFF252836);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: kAmber, brightness: b).copyWith(
    primary: kAmber,
    onPrimary: _darkBg,
    secondary: kTeal,
    surface: dark ? _darkSurface : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? _darkBg : const Color(0xFFF4F5FA),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: kAmber.withAlpha(51),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAmber,
      foregroundColor: _darkBg,
    ),
  );
}
