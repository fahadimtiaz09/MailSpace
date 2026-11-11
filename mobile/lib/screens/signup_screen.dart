// signup_screen.dart — wireframe A2 · Sign up
// Uses the REAL server: ApiClient.instance.signup(...)  →  POST /api/auth/signup
//
//   ① Username  → becomes the email address (live preview)
//   ② Password  → 4-bar strength meter
//   ③ Account type: Regular / Temporary 15 days / Temporary 30 days
//   ④ Account recovery (optional, tap to open)
//   ⑤ Create account → Inbox ('/home')   ·   "Log in" → A3 ('/login')

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/theme_button.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static const mailDomain = 'fahadimtiaz.site';

  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _recoveryEmailCtrl = TextEditingController();
  final _questionCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();

  String _accountType = 'regular'; // 'regular' | 'temp15' | 'temp30'
  bool _hidePassword = true;
  bool _showRecovery = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Redraw while typing: live address preview + strength meter.
    _usernameCtrl.addListener(() => setState(() {}));
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_usernameCtrl, _passwordCtrl, _confirmCtrl, _recoveryEmailCtrl, _questionCtrl, _answerCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Same rule as the backend: 3–20 chars, a-z 0-9 . _ , no ".." and no dot at the ends.
  String? _checkUsername(String u) {
    if (!RegExp(r'^[a-z0-9._]{3,20}$').hasMatch(u) || u.contains('..') || u.startsWith('.') || u.endsWith('.')) {
      return 'Username must be 3–20 characters: lowercase letters, numbers, dot or underscore.';
    }
    return null;
  }

  /// Weak = red, ok = amber, strong = green (like the website).
  Color _barColor(int bars) => bars <= 1 ? AppColors.error : bars == 2 ? AppColors.warning : AppColors.success;

  /// 0–4 bars.
  int _strength(String p) {
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[a-zA-Z]').hasMatch(p) && RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) || RegExp(r'[^a-zA-Z0-9]').hasMatch(p)) score++;
    return score.clamp(1, 4);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final username = _usernameCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text;

    // Check on the phone first, so the user gets a quick answer.
    final usernameProblem = _checkUsername(username);
    String? problem;
    if (usernameProblem != null) {
      problem = usernameProblem;
    } else if (password.length < 8 || password.length > 128) {
      problem = 'Password must be between 8 and 128 characters.';
    } else if (password != _confirmCtrl.text) {
      problem = 'The two passwords don\'t match.';
    } else if ((_questionCtrl.text.trim().isEmpty) != (_answerCtrl.text.trim().isEmpty)) {
      problem = 'For the security question, fill in both the question and an answer.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiClient.instance.signup(
        username: username,
        password: password,
        accountType: _accountType,
        recoveryEmail: _recoveryEmailCtrl.text.trim(),
        securityQuestion: _questionCtrl.text.trim(),
        securityAnswer: _answerCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message); // e.g. "That username is already taken."
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = _usernameCtrl.text.trim().toLowerCase();
    final preview = '${typed.isEmpty ? 'yourname' : typed}@$mailDomain';
    final bars = _strength(_passwordCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: const [ThemeButton(), SizedBox(width: 12)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            // Error box
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  border: Border.all(color: AppColors.error, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 14)),
              ),
              const SizedBox(height: 14),
            ],

            // ① Username + live address preview
            const _Label('Username'),
            TextField(
              controller: _usernameCtrl,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'username'),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Your address: '),
                TextSpan(text: preview, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              ]),
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),

            // ② Password + strength meter
            const _Label('Password'),
            TextField(
              controller: _passwordCtrl,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i < bars ? _barColor(bars) : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 4),
            Text('At least 8 characters. Longer is stronger.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 16),

            const _Label('Confirm password'),
            TextField(
              controller: _confirmCtrl,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 18),

            // ③ Account type
            const _Label('Account type'),
            _AccountTypeOption(
              title: 'Regular',
              subtitle: 'Your account doesn\'t expire.',
              value: 'regular',
              selected: _accountType,
              onTap: (v) => setState(() => _accountType = v),
            ),
            _AccountTypeOption(
              title: 'Temporary — 15 days',
              subtitle: 'Deleted with its messages after 15 days.',
              value: 'temp15',
              selected: _accountType,
              onTap: (v) => setState(() => _accountType = v),
            ),
            _AccountTypeOption(
              title: 'Temporary — 30 days',
              subtitle: 'Deleted with its messages after 30 days.',
              value: 'temp30',
              selected: _accountType,
              onTap: (v) => setState(() => _accountType = v),
            ),
            const SizedBox(height: 10),

            // ④ Account recovery (tap to open / close)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _showRecovery = !_showRecovery),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          const Text('Account recovery ', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text('(optional)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          const Spacer(),
                          Icon(_showRecovery ? Icons.expand_less : Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                  if (_showRecovery)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'If you forget your password, these help you get back in. '
                            'You can add them later in Settings.',
                            style: TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                          const SizedBox(height: 12),
                          const _Label('Recovery email'),
                          TextField(
                            controller: _recoveryEmailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(hintText: 'you@gmail.com'),
                          ),
                          const SizedBox(height: 12),
                          const _Label('Security question'),
                          TextField(
                            controller: _questionCtrl,
                            decoration: const InputDecoration(hintText: 'e.g. What was your first school?'),
                          ),
                          const SizedBox(height: 12),
                          const _Label('Answer'),
                          TextField(
                            controller: _answerCtrl,
                            decoration: const InputDecoration(hintText: 'Something only you know'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Text(
              'To keep MailSpace safe, messages and attachments may be reviewed by administrators '
              'for illegal or harmful content. By creating an account you agree to this.',
              style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
            ),
            const SizedBox(height: 18),

            // ⑤ Create account
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Create account'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Have an account? ', style: TextStyle(fontSize: 14)),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One tappable account-type card. Selected card gets a thick dark border.
class _AccountTypeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const _AccountTypeOption({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOn = value == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isOn ? AppColors.primarySofter : AppColors.surface,
            border: Border.all(color: isOn ? AppColors.primary : AppColors.border, width: isOn ? 2 : 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isOn ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isOn ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
