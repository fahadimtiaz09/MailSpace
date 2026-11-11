// theme.dart — colours, buttons and text boxes for the whole app.
// Matches the wireframes: dark grey ink, white / light-grey backgrounds,
// rounded corners. Change a colour here and every screen updates.

import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF2B2B29);        // main text, primary buttons
  static const muted = Color(0xFF5F5F5A);      // small grey text
  static const border = Color(0xFFCFCFCB);     // card / divider lines
  static const inputBorder = Color(0xFF9A9A95);
  static const surface = Color(0xFFFFFFFF);    // screen background
  static const soft = Color(0xFFF4F4F2);       // unread rows, info boxes
  static const selected = Color(0xFFE4E4E1);   // selected item
  static const brandPanel = Color(0xFF3A3A37); // avatar, dark panels
  static const error = Color(0xFFB42318);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.ink,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.error,
    );

    final roundedBox = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),

      // Big dark button: "Create account", "Log in", "Send"
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: roundedBox,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // Outline button: "Log in" on the Welcome screen
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(50),
          shape: roundedBox,
          side: const BorderSide(color: Color(0xFF4A4A46), width: 1.5),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // Text boxes: username, password, ...
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.ink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1.5, space: 0),
    );
  }
}
