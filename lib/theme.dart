import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _primary = Color(0xFF00E5C3);
  static const _surface = Color(0xFF0A0E1A);
  static const _card = Color(0xFF121829);
  static const _cardBorder = Color(0xFF1E2540);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8B95B0);
  static const _error = Color(0xFFFF4B6E);
  static const _success = Color(0xFF00E5C3);
  static const _warning = Color(0xFFFFB74D);

  static Color get primary => _primary;
  static Color get surface => _surface;
  static Color get card => _card;
  static Color get cardBorder => _cardBorder;
  static Color get textSecondary => _textSecondary;
  static Color get error => _error;
  static Color get success => _success;
  static Color get warning => _warning;

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _surface,
    primaryColor: _primary,
    colorScheme: ColorScheme.dark(
      primary: _primary,
      surface: _surface,
      error: _error,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: _textPrimary,
      displayColor: _textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _surface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: _card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primary, width: 2),
      ),
      hintStyle: TextStyle(color: _textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: _surface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
