// main.dart — app start + list of screens (routes).
//
// When the app opens it asks the server "who is logged in?" (GET /api/auth/me):
//   logged in      → '/home'  (Inbox — temporary page for now)
//   not logged in  → '/'      (A1 Welcome)
//
// Routes:
//   '/'        → A1 Welcome          ✓
//   '/login'   → A3 Log in           ✓
//   '/signup'  → A2 Sign up          ✓
//   '/forgot'  → A4 Forgot password  (later)
//   '/home'    → A5 Inbox            (later — temporary page for now)

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'models/user.dart';
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
        '/forgot': (context) => const _ComingSoon(title: 'Reset password'),
        '/home': (context) => const _LoggedInPage(),
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
        return snapshot.data != null ? const _LoggedInPage() : const WelcomeScreen();
      },
    );
  }
}

/// TEMPORARY page after login, until the real Inbox (A5) is built.
/// Shows who is logged in and has a Log out button, so we can test.
class _LoggedInPage extends StatefulWidget {
  const _LoggedInPage();

  @override
  State<_LoggedInPage> createState() => _LoggedInPageState();
}

class _LoggedInPageState extends State<_LoggedInPage> {
  late final Future<User?> _user = ApiClient.instance.me();

  Future<void> _logout() async {
    try {
      await ApiClient.instance.logout();
    } catch (_) {
      // even if the server didn't answer, cookies were cleared on the phone
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox (coming soon)')),
      body: Center(
        child: FutureBuilder<User?>(
          future: _user,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(color: AppColors.ink);
            }
            final user = snapshot.data;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 56, color: AppColors.ink),
                  const SizedBox(height: 12),
                  Text(
                    user == null ? 'Not logged in' : 'Logged in as\n${user.email}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  if (user != null && user.isTemporary) ...[
                    const SizedBox(height: 6),
                    Text('Temporary account · ${user.daysLeft} days left',
                        style: const TextStyle(color: AppColors.muted)),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton(onPressed: _logout, child: const Text('Log out')),
                ],
              ),
            );
          },
        ),
      ),
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
