// call_service.dart — keeps the app "online" and listens for incoming calls.
//
// While you are logged in, every 4 seconds the app tells the server
// "I'm online" (POST /api/calls/heartbeat). People who open one of your
// emails then see a blue 📞 / 🎥 button. The same answer tells us if someone
// is calling → the call screen opens on top of whatever screen you are on.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../screens/call_screen.dart';

/// Lets the call screen open from anywhere (set in main.dart).
final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  static const heartbeatEvery = Duration(seconds: 4);

  Timer? _timer;
  String? myEmail;          // the logged-in address
  String? activeCallId;     // sent with the heartbeat to keep the call alive
  bool inCall = false;
  final Set<String> _handled = {}; // incoming calls already shown / declined

  void start(String email) {
    myEmail = email;
    _timer ??= Timer.periodic(heartbeatEvery, (_) => _beat());
    _beat();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void markHandled(String id) => _handled.add(id);

  Future<void> _beat() async {
    try {
      final incoming = await ApiClient.instance.callHeartbeat(callId: activeCallId);
      if (incoming == null || inCall) return;
      final id = incoming['id'] as String;
      if (_handled.contains(id)) return;
      _handled.add(id);
      navigatorKey.currentState?.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen.incoming(incoming),
      ));
    } on ApiException catch (e) {
      if (e.statusCode == 401) stop(); // logged out
    } catch (_) {/* no internet for a moment — try again next time */}
  }

  /// Start a call to [email]. kind: 'audio' or 'video'.
  void call(String email, String kind) {
    if (inCall) {
      showMessage('You are already in a call.');
      return;
    }
    navigatorKey.currentState?.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen.outgoing(other: email, kind: kind),
    ));
  }

  static void showMessage(String text) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}
