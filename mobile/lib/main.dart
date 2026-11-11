// main.dart — app start + list of screens (routes).
//
// When the app opens it asks the server "who is logged in?" (GET /api/auth/me):
//   logged in      → HomeShell (Mail / Domains / Settings tabs)
//   not logged in  → A1 Welcome
//
// Routes:
//   '/welcome'  → A1 Welcome          ✓
//   '/login'    → A3 Log in           ✓
//   '/signup'   → A2 Sign up          ✓
//   '/home'     → A5 Inbox + tabs     ✓
//   '/read'     → A7 Read message     (next step)
//   '/compose'  → A8 Compose          (later)
//   '/forgot'   → A4 Forgot password  (later)

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'models/user.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // needed before init() reads phone storage
  await ApiClient.instance.init();
  runApp(const MailSpaceApp());
}

class MailSpaceApp extends StatelessWidget {
  const MailSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MailSpace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const StartScreen(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => const HomeShell(),
        '/read': (context) => const _ComingSoon(title: 'Message'),
        '/compose': (context) => const _ComingSoon(title: 'New message'),
        '/forgot': (context) => const _ComingSoon(title: 'Reset password'),
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
          return const Scaffold(
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

/// Temporary page for screens we haven't built yet.
class _ComingSoon extends StatelessWidget {
  final String title;
  const _ComingSoon({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('This screen is coming in a later step.')),
    );
  }
}
