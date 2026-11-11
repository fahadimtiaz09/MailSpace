// login_screen.dart — wireframe A3 · Log in
// Uses the REAL server: ApiClient.instance.login(...)  →  POST /api/auth/login
//
//   Back arrow           → A1 Welcome
//   Forgot password?     → A4  (route '/forgot', coming later)
//   Log in (success)     → Inbox (route '/home')
//   Create an account    → A2 Sign up (route '/signup')

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _hidePassword = true; // eye icon
  bool _loading = false;     // true while waiting for the server
  String? _error;            // red message box (null = hidden)

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus(); // close the keyboard

    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (login.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiClient.instance.login(login, password);
      if (!mounted) return;
      // Go to the inbox and remove Welcome/Login from the back stack,
      // so the phone's back button doesn't return to the login page.
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message); // e.g. "Wrong username or password."
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(), // just the back arrow, like the wireframe
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Log in to open your inbox.',
              style: TextStyle(fontSize: 15, color: AppColors.muted),
            ),
            const SizedBox(height: 24),

            // ① Error box — only visible when there is an error
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF1F0),
                  border: Border.all(color: AppColors.error, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 14)),
              ),
              const SizedBox(height: 16),
            ],

            // Username or email
            const _Label('Username or email'),
            TextField(
              controller: _loginCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'nimra or nimra@fahadimtiaz.site'),
            ),
            const SizedBox(height: 16),

            // ② Password with eye button
            const _Label('Password'),
            TextField(
              controller: _passwordCtrl,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _loading ? null : _submit(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                ),
              ),
            ),

            // ③ Forgot password? (right side)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/forgot'),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),

            // Log in button — shows a spinner while waiting
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Log in'),
            ),
            if (_loading) ...[
              const SizedBox(height: 10),
              const Text(
                'Connecting… the first login can take up to a minute if the server was asleep.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 32),

            // ⑤ New to MailSpace? Create an account
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('New to MailSpace? ', style: TextStyle(fontSize: 14)),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                  child: const Text('Create an account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small bold label above a text box.
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
