import 'package:flutter/material.dart';

class AppTheme {
  // 深色主题：原有配色
  static const _darkPrimary = Color(0xFF1A1A2E);
  static const _darkAccent = Color(0xFFE94560);
  static const _darkSurface = Color(0xFF16213E);
  static const _darkCard = Color(0xFF0F3460);

  // 浅色主题：更中性、柔和，适合中文 35+ 用户
  static const _lightBg = Color(0xFFF7F7FA);
  static const _lightSurface = Colors.white;
  static const _lightAccent = Color(0xFFE94560);
  static const _lightText = Color(0xFF1B1B2A);
  static const _lightTextSub = Color(0xFF5A6175);
  static const _lightTextHint = Color(0xFF9AA0B2);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _darkPrimary,
        colorScheme: const ColorScheme.dark(
          primary: _darkAccent,
          surface: _darkSurface,
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        cardTheme: const CardThemeData(
          color: _darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _darkPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontSize: 15),
          bodyMedium: TextStyle(color: Color(0xFFB0B8C8), fontSize: 13),
          labelSmall: TextStyle(color: Color(0xFF6B7A99), fontSize: 11),
        ),
      );

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _lightBg,
        colorScheme: const ColorScheme.light(
          primary: _lightAccent,
          surface: _lightSurface,
          onPrimary: Colors.white,
          onSurface: _lightText,
        ),
        cardTheme: const CardThemeData(
          color: _lightSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFFE6E8EF)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _lightBg,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: _lightText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: _lightText),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: _lightText, fontSize: 15),
          bodyMedium: TextStyle(color: _lightTextSub, fontSize: 13),
          labelSmall: TextStyle(color: _lightTextHint, fontSize: 11),
        ),
      );
}
