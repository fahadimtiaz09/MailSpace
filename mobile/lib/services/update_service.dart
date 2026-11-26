// update_service.dart — "Update available" for the APK from domailit.com.
//
// The app isn't on Google Play, so it can't update itself. Instead, once per
// start it asks the server for the newest version (GET /api/app/android) and,
// if that is newer than this build, offers to download it from the website.
// Installing the new APK keeps the user's login and settings.
//
// APP_BUILD is set by mobile/publish_android.ps1 (--dart-define=APP_BUILD=<build>).
// A build made without it (flutter run) never asks.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../theme.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const int thisBuild = int.fromEnvironment('APP_BUILD');
  bool _checked = false;

  Future<void> checkOnce(BuildContext context) async {
    if (_checked || thisBuild == 0) return;
    _checked = true;
    Map<String, dynamic>? latest;
    try {
      latest = await ApiClient.instance.latestAndroidVersion();
    } catch (_) {
      return; // no internet / nothing published — try again next start
    }
    final build = latest?['build'];
    if (latest == null || build is! int || build <= thisBuild || !context.mounted) return;

    final name = (latest['version_name'] as String?) ?? '';
    final notes = (latest['notes'] as String?) ?? '';
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.system_update_alt, color: AppColors.primary, size: 32),
        title: Text(name.isEmpty ? 'Update available' : 'DoMailit $name is here'),
        content: Text(notes.isNotEmpty
            ? notes
            : 'A newer version of DoMailit is ready. Download it and tap Install — '
                'you\'ll stay logged in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
        ],
      ),
    );
    if (yes == true) {
      final site = ApiClient.baseUrl.replaceFirst(RegExp(r'/api$'), '');
      await launchUrl(Uri.parse('$site${latest['url'] ?? '/download/android'}'),
          mode: LaunchMode.externalApplication);
    }
  }
}
