// screen_guard.dart — protects emails from screenshots.
//
// Talks to the phone's own code (MainActivity.kt on Android, AppDelegate.swift
// on iPhone) through a "method channel":
//   • ScreenGuard.secure(true)  → Android: screenshots & screen recording are
//                                 blocked (the picture comes out black).
//   • onScreenshot              → called when the phone says a screenshot was
//                                 taken (iPhone always, Android 14+).
// On the website (Chrome) this does nothing.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenGuard {
  static const _channel = MethodChannel('mailspace/screen_guard');
  static void Function()? onScreenshot;
  static bool _ready = false;

  static void init() {
    if (_ready || kIsWeb) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'screenshot') onScreenshot?.call();
      return null;
    });
  }

  /// Turn the screenshot block on (reading an email) or off (leaving it).
  static Future<void> secure(bool on) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('secure', on);
    } catch (_) {/* older app build without the native part */}
  }

  /// "android" / "ios" — sent to the server so the alert email says where.
  static String get platformName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}
