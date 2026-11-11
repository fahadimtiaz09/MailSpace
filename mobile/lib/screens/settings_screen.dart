// settings_screen.dart — wireframe A12 · Settings  (the "Settings" tab)
//
//   ① Profile: username, address, account type, days left   (GET /api/auth/me)
//   ② Appearance: Light / Dark / System  (saved on the phone)
//   ③ Sending addresses (From list)                          (GET /api/domains/from-addresses)
//   ④ Security: change password, recovery email, security question
//                                                            (POST /api/auth/change-password, /recovery)
//   ⑥ Log out                                                (POST /api/auth/logout) → A1 Welcome

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/message_row.dart';

class SettingsScreen extends StatefulWidget {
  final User user;
  final VoidCallback onOpenDomains;
  const SettingsScreen({super.key, required this.user, required this.onOpenDomains});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiClient.instance;
  late User _user = widget.user;
  List<String>? _fromAddresses;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([_api.me(), _api.getFromAddresses()]);
      if (!mounted) return;
      setState(() {
        final u = results[0] as User?;
        if (u != null) _user = u;
        _fromAddresses = results[1] as List<String>;
      });
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need your password to log in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Log out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _api.logout();
    } catch (_) {
      // cookies are cleared on the phone anyway
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
  }

  Future<void> _openForm(Widget page) async {
    final done = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => page));
    if (done != null) {
      _snack(done);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final typeText = switch (u.accountType) {
      'temp15' => 'Temporary — 15 days',
      'temp30' => 'Temporary — 30 days',
      _ => 'Regular',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      body: RefreshIndicator(
      color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // ① profile
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Avatar(seed: u.email, text: u.initials, radius: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.username, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text(u.email, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                        Text(u.isTemporary ? '$typeText · ${u.daysLeft} days left' : typeText,
                            style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _kv('Member since', u.createdAt == null ? '—' : MessageRow.fullTime(u.createdAt).split(',').first),
            if (u.expiresAt != null) _kv('Account expires', MessageRow.fullTime(u.expiresAt)),

            // ② appearance
            const _Section('Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.phone_android)),
                ],
                selected: {themeController.value},
                onSelectionChanged: (s) => themeController.set(s.first),
                showSelectedIcon: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text('Saved on this phone. "System" follows your phone\'s light or dark setting.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),

            // ③ sending addresses
            const _Section('Sending addresses'),
            if (_fromAddresses == null)
              Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(color: AppColors.primary))
            else
              for (final (i, a) in _fromAddresses!.indexed)
                ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: Text(a, overflow: TextOverflow.ellipsis),
                  trailing: Text(i == 0 ? 'Main' : 'Domain',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.muted, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400)),
                ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('My domains'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onOpenDomains,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text('Mail to Gmail, Outlook and other providers can only be sent from your main address.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),

            // ④ security
            const _Section('Security'),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openForm(const _ChangePasswordPage()),
            ),
            ListTile(
              leading: const Icon(Icons.mail_lock_outlined),
              title: const Text('Recovery email'),
              subtitle: Text(u.recoveryEmail ?? 'Not set up'),
              trailing: Text(u.recoveryEmail == null ? 'Set up' : 'Change',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _openForm(const _RecoveryPage(question: false)),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Security question'),
              subtitle: Text(u.securityQuestion ?? 'Not set up', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(u.securityQuestion == null ? 'Set up' : 'Change',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _openForm(const _RecoveryPage(question: true)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '• Your password is stored only as a secure hash.\n'
                '• Repeated failed logins are slowed down automatically.\n'
                '• Messages are shown as plain text, so scripts inside an email can\'t run.',
                style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.muted),
              ),
            ),

            // Admin console (admins only)
            if (u.isAdmin) ...[
              const _Section('Admin'),
              ListTile(
                leading: Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
                title: const Text('Admin console'),
                subtitle: const Text('Users, all mail, flagged messages, audit log'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, '/admin'),
              ),
            ],

            // ⑥ log out
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.logout, color: AppColors.error),
              title: Text('Log out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Expanded(child: Text(k, style: TextStyle(fontSize: 13, color: AppColors.muted))),
            Text(v, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.muted)),
      );
}

// ---------------------------------------------------------------------------
// Small form pages opened from Security
// ---------------------------------------------------------------------------

class _FormPage extends StatelessWidget {
  final String title;
  final String? error;
  final bool busy;
  final String buttonText;
  final VoidCallback onSave;
  final List<Widget> fields;

  const _FormPage({
    required this.title,
    required this.error,
    required this.busy,
    required this.buttonText,
    required this.onSave,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (error != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  border: Border.all(color: AppColors.error, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(error!, style: TextStyle(color: AppColors.error, fontSize: 14)),
              ),
              const SizedBox(height: 16),
            ],
            ...fields,
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : onSave,
              child: busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _field(String label, TextEditingController c, {bool secret = false, String? hint, TextInputType? type}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: secret,
            keyboardType: type,
            autocorrect: !secret,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );

class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage();

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_new.text.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'The two new passwords don\'t match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.changePassword(_current.text, _new.text);
      if (mounted) Navigator.pop(context, 'Password changed');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormPage(
        title: 'Change password',
        error: _error,
        busy: _busy,
        buttonText: 'Save password',
        onSave: _save,
        fields: [
          _field('Current password', _current, secret: true),
          _field('New password', _new, secret: true, hint: 'At least 8 characters'),
          _field('Confirm new password', _confirm, secret: true),
        ],
      );
}

/// Recovery email (question: false) or security question (question: true).
class _RecoveryPage extends StatefulWidget {
  final bool question;
  const _RecoveryPage({required this.question});

  @override
  State<_RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<_RecoveryPage> {
  final _current = TextEditingController();
  final _email = TextEditingController();
  final _q = TextEditingController();
  final _a = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _email, _q, _a]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (widget.question && (_q.text.trim().isEmpty || _a.text.trim().length < 2)) {
      setState(() => _error = 'Fill in both the security question and an answer.');
      return;
    }
    if (!widget.question && _email.text.trim().isEmpty) {
      setState(() => _error = 'Type your recovery email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.setRecovery(
        currentPassword: _current.text,
        recoveryEmail: widget.question ? null : _email.text.trim(),
        securityQuestion: widget.question ? _q.text.trim() : null,
        securityAnswer: widget.question ? _a.text.trim() : null,
      );
      if (mounted) Navigator.pop(context, widget.question ? 'Security question saved' : 'Recovery email saved');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormPage(
        title: widget.question ? 'Security question' : 'Recovery email',
        error: _error,
        busy: _busy,
        buttonText: 'Save',
        onSave: _save,
        fields: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.question
                  ? 'A question only you can answer — a backup way to reset your password.'
                  : 'If you forget your password, we can email a reset code here.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          if (widget.question) ...[
            _field('Question', _q, hint: 'e.g. What was your first school?'),
            _field('Answer', _a, hint: 'Something only you know'),
          ] else
            _field('Recovery email', _email, hint: 'you@gmail.com', type: TextInputType.emailAddress),
          _field('Current password', _current, secret: true, hint: 'Needed to save this change'),
        ],
      );
}
