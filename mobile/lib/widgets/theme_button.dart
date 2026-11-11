// theme_button.dart — 🌙 / ☀️ button, like the theme switch on the website.
// Works before login too (Welcome, Log in, Sign up, Forgot password).
// One tap switches between Light and Dark. The choice is saved on the phone,
// and Settings → Appearance shows the same choice (plus "System").

import 'package:flutter/material.dart';

import '../theme.dart';

class ThemeButton extends StatelessWidget {
  /// true on the dark-blue Welcome panel (white icon).
  final bool onDark;
  const ThemeButton({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: onDark ? Colors.white : AppColors.ink,
      ),
      style: IconButton.styleFrom(
        backgroundColor: onDark ? Colors.white.withValues(alpha: .12) : AppColors.surface,
        side: onDark ? BorderSide.none : BorderSide(color: AppColors.border),
        minimumSize: const Size(44, 44),
      ),
      onPressed: () => themeController.set(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
