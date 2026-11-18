// people.dart — names and profile pictures of DoMailit addresses.
//
// Every Avatar asks for its picture. The questions are collected for a moment
// and sent to the server in one go (GET /api/people?emails=a,b,c); pictures are
// downloaded once and kept in memory. Gmail and other outside addresses keep
// their coloured initials.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

class People extends ChangeNotifier {
  People._();
  static final People instance = People._();

  final Map<String, Uint8List> _photos = {};
  final Map<String, String> _names = {};
  final Set<String> _asked = {};
  final Set<String> _queue = {};
  Timer? _timer;

  Uint8List? photoOf(String email) => _photos[email.toLowerCase()];
  String? nameOf(String email) => _names[email.toLowerCase()];

  void want(String email) {
    final e = email.trim().toLowerCase();
    if (!e.contains('@') || _asked.contains(e)) return;
    _asked.add(e);
    _queue.add(e);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 60), _flush);
  }

  /// Ask again (after you changed your own name or picture).
  void forget(String email) {
    final e = email.trim().toLowerCase();
    _asked.remove(e);
    _photos.remove(e);
    _names.remove(e);
    notifyListeners();
    want(e);
  }

  Future<void> _flush() async {
    final emails = _queue.toList();
    _queue.clear();
    final api = ApiClient.instance;
    for (var i = 0; i < emails.length; i += 60) {
      final batch = emails.sublist(i, i + 60 > emails.length ? emails.length : i + 60);
      Map<String, Map<String, dynamic>> found;
      try {
        found = await api.people(batch);
      } catch (_) {
        batch.forEach(_asked.remove); // try again next time
        continue;
      }
      var changed = false;
      for (final entry in found.entries) {
        final name = entry.value['name'] as String?;
        if (name != null && name.isNotEmpty) {
          _names[entry.key] = name;
          changed = true;
        }
        final url = entry.value['avatar'] as String?;
        if (url != null) {
          final bytes = await api.avatarBytes(url);
          if (bytes != null) {
            _photos[entry.key] = bytes;
            changed = true;
          }
        }
      }
      if (changed) notifyListeners();
    }
  }
}
