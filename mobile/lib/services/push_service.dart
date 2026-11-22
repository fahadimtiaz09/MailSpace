// push_service.dart — phone notifications for new email and calls
// (Firebase Cloud Messaging, free). The server side is backend/push.py.
//
//   App closed / in the background → Android shows the notification itself.
//   App open                       → a small bar at the bottom ("New email from …").
//   Tap a notification             → the email opens (a call opens the app, and
//                                    the call screen appears as it keeps ringing).

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../firebase_options.dart';
import 'call_service.dart';

/// Runs when a message arrives while the app is closed. Android already shows
/// the notification, so there is nothing else to do here.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _ready = false;     // Firebase started
  bool _linked = false;    // token sent to the server for this login
  String? _openedId;       // last email opened from a notification (no double opens)

  /// Call once in main(), before runApp.
  Future<void> init() async {
    if (!Platform.isAndroid || !DefaultFirebaseOptions.configured) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
      FirebaseMessaging.onMessage.listen(_whileOpen);
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (_linked) _send(token);
      });
      _ready = true;
    } catch (_) {
      // Wrong Firebase values or no Google Play services → no notifications, app still works
    }
  }

  /// After login (HomeShell): ask permission, give the server this phone's address.
  Future<void> afterLogin() async {
    if (!_ready || _linked) return;
    _linked = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _send(token);
      // The app was started by tapping a notification
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _open(first);
    } catch (_) {
      _linked = false; // try again next time
    }
  }

  /// Before logout: stop notifications for this phone, so the next person
  /// who logs in here doesn't get yours.
  Future<void> beforeLogout() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiClient.instance.pushUnsubscribe(token);
    } catch (_) {/* the server forgets unused phones by itself */}
    await forget();
  }

  /// Leaving this account but another one stays signed in on the phone:
  /// the next account takes over this phone's notifications (afterLogin).
  Future<void> beforeSwitch({bool unsubscribe = false}) async {
    if (unsubscribe && _ready) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await ApiClient.instance.pushUnsubscribe(token);
      } catch (_) {}
    }
    _linked = false;
  }

  /// The account is gone (deleted) — just drop this phone's token.
  Future<void> forget() async {
    _linked = false;
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> _send(String token) => ApiClient.instance.pushSubscribe(token);

  void _whileOpen(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'call') return; // the app is open, so the call screen is already ringing
    final title = message.notification?.title ?? message.data['title'] ?? 'DoMailit';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$title — $body', maxLines: 2, overflow: TextOverflow.ellipsis),
        action: message.data['entry_id'] == null
            ? null
            : SnackBarAction(label: 'Open', onPressed: () => _open(message)),
        duration: const Duration(seconds: 5),
      ));
  }

  void _open(RemoteMessage message) {
    final id = message.data['entry_id'];
    if (id == null || id.isEmpty || id == _openedId) return;
    _openedId = id;
    navigatorKey.currentState?.pushNamed('/read', arguments: id);
  }
}
