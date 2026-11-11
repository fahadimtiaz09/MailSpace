// theme.dart — colours, font and buttons for the whole app.
// Same palette as the website (frontend/style.css), in light AND dark.
//
// How dark mode works:
//   • themeController holds the choice: Light / Dark / System (saved on the phone).
//   • AppColors.dark is true when the app should look dark.
//   • When the choice changes, main.dart rebuilds every screen so all
//     AppColors.* values update at once.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  /// Set by main.dart. Don't change it yourself — use themeController.
  static bool dark = false;

  static Color _pick(int light, int darkValue) => Color(dark ? darkValue : light);

  // Backgrounds
  static Color get bg => _pick(0xFFF7F9FF, 0xFF0B1220);          // page background
  static Color get bg2 => _pick(0xFFEEF2FF, 0xFF101B2D);         // search box, chips
  static Color get surface => _pick(0xFFFFFFFF, 0xFF16243A);     // cards, lists, bars
  static Color get surface2 => _pick(0xFFF8FAFE, 0xFF132036);    // quiet fill
  static Color get elevated => _pick(0xFFFFFFFF, 0xFF1B2C45);    // dialogs, drawer

  // Brand blue
  static Color get primary => _pick(0xFF2459D6, 0xFF5B91FF);     // links, active things
  static Color get primaryBtn => _pick(0xFF2459D6, 0xFF346DE0);  // filled buttons
  static Color get primarySoft => _pick(0xFFE3ECFF, 0x295B91FF); // selected item
  static Color get primarySofter => _pick(0xFFF0F5FF, 0x145B91FF); // info boxes
  static Color get navy => _pick(0xFF142B50, 0xFF0A1324);

  // Text
  static Color get ink => _pick(0xFF172B4D, 0xFFF1F5FC);         // main text
  static Color get muted => _pick(0xFF64748B, 0xFFA6B5C9);       // secondary text
  static Color get faint => _pick(0xFF8592A6, 0xFF7D8EA6);       // hints

  // Lines
  static Color get border => _pick(0xFFE3E9F2, 0xFF293A53);
  static Color get inputBorder => _pick(0xFFD2DBE9, 0xFF354A68);

  // Status
  static Color get success => _pick(0xFF16A36A, 0xFF35C78A);
  static Color get successSoft => _pick(0xFFE2F6EC, 0x2435C78A);
  static Color get warning => _pick(0xFFE9A23B, 0xFFF2B65B);     // stars
  static Color get warningSoft => _pick(0xFFFDF2DE, 0x24F2B65B);
  static Color get error => _pick(0xFFD94A55, 0xFFF17882);
  static Color get errorText => _pick(0xFFBD3440, 0xFFF58D96);
  static Color get errorSoft => _pick(0xFFFCE8EA, 0x24F17882);

  // Old names kept so every screen still works
  static Color get soft => surface2;
  static Color get selected => primarySoft;
  static Color get brandPanel => primaryBtn;

  /// Avatar colours like the website: each address gets its own hue.
  static (Color background, Color text) avatar(String seed) {
    var hash = 0;
    for (final c in seed.toLowerCase().runes) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    return dark
        ? (HSLColor.fromAHSL(1, hue, .45, .26).toColor(), HSLColor.fromAHSL(1, hue, .55, .80).toColor())
        : (HSLColor.fromAHSL(1, hue, .62, .92).toColor(), HSLColor.fromAHSL(1, hue, .55, .38).toColor());
  }
}

/// Light / Dark / System — saved on the phone.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static const _key = 'theme_mode';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = switch (prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // keep System
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

final themeController = ThemeController();

class AppTheme {
  /// Builds the theme from the current AppColors (light or dark).
  static ThemeData build() {
    final isDark = AppColors.dark;
    final base = ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      // Plus Jakarta Sans — the same font as the website — for ALL text.
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2459D6),
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: AppColors.primaryBtn,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.error,
      outline: AppColors.inputBorder,
      outlineVariant: AppColors.border,
    );

    OutlineInputBorder box(Color c, double w) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryBtn,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primaryBtn.withValues(alpha: .55),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: rounded,
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: AppColors.surface,
          minimumSize: const Size.fromHeight(50),
          shape: rounded,
          side: BorderSide(color: AppColors.inputBorder, width: 1.5),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryBtn,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: box(AppColors.inputBorder, 1.5),
        enabledBorder: box(AppColors.inputBorder, 1.5),
        focusedBorder: box(AppColors.primary, 2),
        errorBorder: box(AppColors.error, 1.5),
        focusedErrorBorder: box(AppColors.error, 2),
        hintStyle: TextStyle(color: AppColors.faint),
        suffixIconColor: AppColors.muted,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1, space: 0),
      drawerTheme: DrawerThemeData(backgroundColor: AppColors.elevated),
      dialogTheme: DialogThemeData(backgroundColor: AppColors.elevated),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.elevated),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.dark ? AppColors.elevated : AppColors.navy,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
        actionTextColor: const Color(0xFF91B5FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primarySoft,
        side: BorderSide(color: AppColors.border),
        labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.ink, fontWeight: FontWeight.w600),
        checkmarkColor: AppColors.primary,
      ),
      listTileTheme: ListTileThemeData(iconColor: AppColors.muted, textColor: AppColors.ink),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primarySoft : AppColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.ink,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: AppColors.inputBorder)),
        ),
      ),
    );
  }
}

/// Makes every widget build again, so new AppColors show everywhere
/// (called after switching Light / Dark).
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element el) {
    el.markNeedsBuild();
    el.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
