// main.dart — app start + list of screens (routes).
//
// When the app opens it asks the server "who is logged in?" (GET /api/auth/me):
//   logged in      → HomeShell (Mail / Domains / Settings tabs)
//   not logged in  → A1 Welcome
//
// Screens (wireframe number → file):
//   A1  Welcome           screens/welcome_screen.dart   route '/welcome'
//   A2  Sign up           screens/signup_screen.dart    route '/signup'
//   A3  Log in            screens/login_screen.dart     route '/login'
//   A4  Forgot password   screens/forgot_screen.dart    route '/forgot'
//   A5  Inbox             screens/inbox_screen.dart     (Mail tab, route '/home')
//   A6  Folders drawer    screens/inbox_screen.dart     (☰ on the Inbox)
//   A7  Read message      screens/read_screen.dart      route '/read'
//   A8  Compose           screens/compose_screen.dart   route '/compose'
//   A9  Search            screens/search_screen.dart    (🔍 on the Inbox)
//   A10 My domains        screens/domains_screen.dart   (Domains tab)
//   A11 Add / manage domain  screens/domain_detail_screen.dart
//   A12 Settings          screens/settings_screen.dart  (Settings tab)
//   Admin console         screens/admin_screen.dart     route '/admin' (admins only)

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'models/user.dart';
import 'screens/admin_screen.dart';
import 'screens/compose_screen.dart';
import 'screens/forgot_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/read_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // needed before init() reads phone storage
  await ApiClient.instance.init();
  await themeController.load(); // Light / Dark / System saved on the phone
  runApp(const MailSpaceApp());
}

class MailSpaceApp extends StatefulWidget {
  const MailSpaceApp({super.key});

  @override
  State<MailSpaceApp> createState() => _MailSpaceAppState();
}

class _MailSpaceAppState extends State<MailSpaceApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // hear when the phone switches light/dark
    themeController.addListener(_applyTheme);
    _setDarkFlag();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeController.removeListener(_applyTheme);
    super.dispose();
  }

  /// Phone switched between light and dark (matters for "System").
  @override
  void didChangePlatformBrightness() => _applyTheme();

  void _setDarkFlag() {
    final phoneIsDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    AppColors.dark = switch (themeController.value) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => phoneIsDark,
    };
  }

  void _applyTheme() {
    _setDarkFlag();
    setState(() {});
    // Redraw every open screen so all colours change straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildAllChildren(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MailSpace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const StartScreen(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/forgot': (context) => const ForgotScreen(),
        '/home': (context) => const HomeShell(),
        '/read': (context) => const ReadScreen(),
        '/compose': (context) => const ComposeScreen(),
        '/admin': (context) => const AdminScreen(),
      },
    );
  }
}

/// First thing the user sees: checks the saved login, then opens
/// the Inbox or the Welcome screen.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final Future<User?> _check = _whoIsLoggedIn();

  Future<User?> _whoIsLoggedIn() async {
    try {
      return await ApiClient.instance.me();
    } catch (_) {
      return null; // no internet / server problem → just show Welcome
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _check,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.ink),
                  SizedBox(height: 16),
                  Text('Connecting to MailSpace…', style: TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          );
        }
        return snapshot.data != null ? const HomeShell() : const WelcomeScreen();
      },
    );
  }
}
