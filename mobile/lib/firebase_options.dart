// firebase_options.dart — the 4 values that connect the app to YOUR Firebase project.
//
// Where to find them: Firebase console → ⚙ Project settings → General →
// "Your apps" → the Android app (com.domailit.app).
// Or open the google-services.json file Firebase gives you:
//   apiKey            → client[0].api_key[0].current_key
//   appId             → client[0].client_info.mobilesdk_app_id
//   messagingSenderId → project_info.project_number
//   projectId         → project_info.project_id
//
// These are not secrets (every Android app carries them). While they are empty,
// the app simply runs without notifications.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const String apiKey = 'AIzaSyA57YvAZIVAvdE6kWYV7c5q3woEdKPsNrg';
  static const String appId = '1:120406568964:android:e110f17e69106700ffc551';
  static const String messagingSenderId = '120406568964';
  static const String projectId = 'domailit-d4d0a';

  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty && projectId.isNotEmpty;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}
