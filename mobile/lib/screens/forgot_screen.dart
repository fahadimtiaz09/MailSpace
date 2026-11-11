// forgot_screen.dart — wireframe A4 · Forgot password
// Same 4 steps as the website, on one screen with a progress bar:
//   1. Username or email          → POST /api/auth/forgot/start
//   2. Choose a way to reset      (email code / security question — only the ones set up)
//   3. Enter the code (sent by     POST /api/auth/forgot/send-code)  or the answer
//   4. New password               → POST /api/auth/forgot/reset
//   Done → back to A3 Log in

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/theme_button.dart';

class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key});

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  final _api = ApiClient.instance;
  final _loginCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 1;          // 1–4
  ForgotInfo? _info;      // what step 1 found
  String? _method;        // 'email' or 'question'
  String? _sentTo;        // masked email the code went to
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_loginCtrl, _codeCtrl, _answerCtrl, _passwordCtrl, _confirmCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Runs a server call with spinner + error box.
  Future<void> _run(Future<void> Function() call) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Step 1
  Future<void> _start() => _run(() async {
        if (_loginCtrl.text.trim().isEmpty) {
          setState(() => _error = 'Enter your username or email.');
          return;
        }
        final info = await _api.forgotStart(_loginCtrl.text);
        if (info.recoveryEmail == null && info.securityQuestion == null) {
          setState(() => _error =
              'This account has no recovery email or security question, so it can\'t be reset here. '
              'Please contact the MailSpace admin.');
          return;
        }
        setState(() {
          _info = info;
          _step = 2;
        });
      });

  // Step 2
  Future<void> _choose(String method) => _run(() async {
        if (method == 'email') {
          _sentTo = await _api.forgotSendCode(_info!.login);
        }
        setState(() {
          _method = method;
          _step = 3;
        });
      });

  // Step 3 → 4 (checked by the server together with the new password in step 4)
  void _next() {
    if (_method == 'email' && !RegExp(r'^\d{6}$').hasMatch(_codeCtrl.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    if (_method == 'question' && _answerCtrl.text.trim().length < 2) {
      setState(() => _error = 'Type your answer.');
      return;
    }
    setState(() {
      _error = null;
      _step = 4;
    });
  }

  // Step 4
  Future<void> _reset() => _run(() async {
        if (_passwordCtrl.text.length < 8) {
          setState(() => _error = 'New password must be at least 8 characters.');
          return;
        }
        if (_passwordCtrl.text != _confirmCtrl.text) {
          setState(() => _error = 'The two passwords don\'t match.');
          return;
        }
        try {
          await _api.forgotReset(
            login: _info!.login,
            method: _method!,
            newPassword: _passwordCtrl.text,
            code: _method == 'email' ? _codeCtrl.text.trim() : null,
            answer: _method == 'question' ? _answerCtrl.text.trim() : null,
          );
        } on ApiException catch (e) {
          // Wrong code / answer → go back to step 3 so it can be fixed.
          if (e.message.contains('code') || e.message.contains('answer')) {
            setState(() => _step = 3);
          }
          rethrow;
        }
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Password reset'),
            content: const Text('You can now log in with your new password.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Go to log in'))],
          ),
        );
        if (mounted) Navigator.pop(context); // back to A3 Log in
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('Step $_step of 4', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ),
          const ThemeButton(),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            // ① progress bar
            Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: i < _step ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

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
              const SizedBox(height: 16),
            ],

            // ② finished steps stay visible but faded
            if (_step > 1) _doneCard('Step 1 — done', 'Account: ${_info!.login}'),
            if (_step > 2)
              _doneCard('Step 2 — done',
                  _method == 'email' ? 'Method: email a code to ${_sentTo ?? ''}' : 'Method: security question'),
            if (_step > 3)
              _doneCard('Step 3 — done', _method == 'email' ? 'Code entered' : 'Answer entered'),

            if (_step == 1) ..._stepOne(),
            if (_step == 2) ..._stepTwo(),
            if (_step == 3) ..._stepThree(),
            if (_step == 4) ..._stepFour(),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepOne() => [
        _heading('Reset your password', 'Enter your username or email to start.'),
        const _Label('Username or email'),
        TextField(
          controller: _loginCtrl,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _busy ? null : _start(),
        ),
        const SizedBox(height: 20),
        _mainButton('Continue', _start),
        const SizedBox(height: 8),
        Center(
          child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to log in')),
        ),
      ];

  List<Widget> _stepTwo() => [
        _heading('Choose a way to reset', 'Verify it\'s you, then set a new password.'),
        if (_info!.recoveryEmail != null)
          _choiceTile(Icons.mail_outline, 'Email a code to', _info!.recoveryEmail!, () => _choose('email')),
        if (_info!.securityQuestion != null)
          _choiceTile(Icons.help_outline, 'Security question', 'Answer your question', () => _choose('question')),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ];

  List<Widget> _stepThree() => _method == 'email'
      ? [
          _heading('Check your email', 'We sent a 6-digit code to ${_sentTo ?? 'your recovery email'}.'),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, letterSpacing: 12, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: '······', counterText: ''),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: _busy ? null : () => _choose('email'), child: const Text('Resend code')),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _step = 2;
                  _error = null;
                }),
                child: const Text('Use another method'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _mainButton('Continue', _next),
        ]
      : [
          _heading('Security question', _info!.securityQuestion ?? ''),
          const _Label('Your answer'),
          TextField(controller: _answerCtrl, onSubmitted: (_) => _next()),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _step = 2;
                _error = null;
              }),
              child: const Text('Use another method'),
            ),
          ),
          const SizedBox(height: 12),
          _mainButton('Continue', _next),
        ];

  List<Widget> _stepFour() => [
        _heading('Set a new password', 'At least 8 characters.'),
        const _Label('New password'),
        TextField(controller: _passwordCtrl, obscureText: true),
        const SizedBox(height: 14),
        const _Label('Confirm new password'),
        TextField(controller: _confirmCtrl, obscureText: true, onSubmitted: (_) => _busy ? null : _reset()),
        const SizedBox(height: 20),
        _mainButton('Reset password', _reset),
      ];

  // ---------------- small building blocks ----------------

  Widget _heading(String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 14, color: AppColors.muted)),
          ],
        ),
      );

  Widget _mainButton(String label, VoidCallback onTap) => FilledButton(
        onPressed: _busy ? null : onTap,
        child: _busy
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(label),
      );

  Widget _doneCard(String title, String text) => Opacity(
        opacity: 0.6,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _choiceTile(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          onPressed: _busy ? null : onTap,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      );
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
