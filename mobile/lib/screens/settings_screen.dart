// settings_screen.dart — wireframe A12 · Settings  (the "Settings" tab)
//
//   ① Profile: picture, name, address, account type, days left
//                (GET /api/auth/me, PATCH /api/auth/profile, POST/DELETE /api/auth/avatar)
//   ② Appearance: Light / Dark / System  (saved on the phone)
//   ③ Sending addresses (From list)                          (GET /api/domains/from-addresses)
//   ④ Privacy: show when I'm online                          (PATCH /api/auth/profile {show_online})
//   ⑤ Security: change password, recovery email, security question
//                                                            (POST /api/auth/change-password, /recovery)
//   ⑥ Log out                                                (POST /api/auth/logout) → A1 Welcome
//   ⑦ Delete account                                         (POST /api/auth/delete-account) → A1 Welcome

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import '../services/people.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/legal.dart';
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

  // ---------------- name + picture ----------------

  Future<void> _afterProfileChange(String done) async {
    People.instance.forget(_user.email); // show the new picture everywhere
    await _refresh();
    _snack(done);
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _user.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Your full name',
            helperText: 'Shown to people you email. Leave empty to show only your address.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null) return;
    try {
      await _api.updateDisplayName(name);
      await _afterProfileChange('Name saved.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  /// Crop to a square and shrink to 256 × 256 PNG (small upload, fast to show).
  static Future<Uint8List> _squarePhoto(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 640);
    final image = (await codec.getNextFrame()).image;
    final side = math.min(image.width, image.height).toDouble();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side, side),
      const Rect.fromLTWH(0, 0, 256, 256),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final out = await recorder.endRecording().toImage(256, 256);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _changePhoto() async {
    // Same picker as Compose (it returns the chosen files directly)
    final List<PlatformFile>? picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked == null || picked.isEmpty) return;
    final f = picked.first;
   final Uint8List? bytes = f.path != null ? await File(f.path!).readAsBytes() : null;
    if (bytes == null) return;
    _snack('Uploading…');
    try {
      await _api.uploadAvatar(await _squarePhoto(bytes));
      await _afterProfileChange('Profile picture updated.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("That file isn't a picture we can read.");
    }
  }

  Future<void> _removePhoto() async {
    try {
      await _api.deleteAvatar();
      await _afterProfileChange('Profile picture removed.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _photoMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_user.avatar == null ? 'Upload photo' : 'Change photo'),
              onTap: () {
                Navigator.pop(context);
                _changePhoto();
              },
            ),
            if (_user.avatar != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.error),
                title: Text('Remove photo', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _logout() async {
    // More than one account on this phone? Offer "this one" or "all of them" (like Gmail).
    var count = 1;
    try {
      count = (await _api.accounts()).length;
    } catch (_) {}
    if (!mounted) return;
    final many = count > 1;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(many
            ? 'Log out of ${widget.user.email} only, or of all $count accounts on this phone?'
            : 'You will need your password to log in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (many)
            TextButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: Text('All accounts', style: TextStyle(color: AppColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'one'),
            child: Text(many ? 'This account' : 'Log out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final all = choice == 'all' || !many;
    if (all) {
      await PushService.instance.beforeLogout();
    } else {
      await PushService.instance.beforeSwitch(unsubscribe: true); // the next account takes over notifications
    }
    var remaining = 0;
    try {
      remaining = await _api.logout(all: all);
    } catch (_) {
      // cookies are cleared on the phone anyway
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, remaining > 0 ? '/home' : '/welcome', (route) => false);
  }

  bool? _savingOnline; // the value being saved, while the request runs

  Future<void> _setShowOnline(bool show) async {
    setState(() => _savingOnline = show);
    try {
      await _api.setShowOnline(show);
      await _refresh();
      _snack(show ? 'People can now see when you\'re online' : 'You now appear offline to everyone');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _savingOnline = null);
    }
  }

  Future<void> _deleteAccount() async {
    // The page returns how many other accounts are still signed in (null = not deleted)
    final remaining = await Navigator.push<int>(
        context, MaterialPageRoute(builder: (context) => const _DeleteAccountPage()));
    if (remaining == null) return;
    await PushService.instance.forget();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, remaining > 0 ? '/home' : '/welcome', (route) => false);
    }
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
                  // tap the picture to change it
                  GestureDetector(
                    onTap: _photoMenu,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Avatar(seed: u.email, text: u.initials, radius: 28),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.bg, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.shownName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text(u.email, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                        Text(u.isTemporary ? '$typeText · ${u.daysLeft} days left' : typeText,
                            style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Name'),
              subtitle: Text(u.displayName ?? 'Not set — people see only your address'),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: _editName,
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

            // notifications
            const _Section('Notifications'),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Send a test notification'),
              subtitle: const Text('New emails and calls pop up on this phone, even when the app is closed.'),
              onTap: () async {
                try {
                  await _api.pushTest();
                  _snack('Sent — it should pop up in a few seconds');
                } on ApiException catch (e) {
                  _snack(e.message);
                }
              },
            ),

            // ④ privacy
            const _Section('Privacy'),
            SwitchListTile(
              // Green dot when people can see you're online, grey ring when hidden
              secondary: _OnlineDot(on: _savingOnline ?? u.showOnline),
              title: const Text('Show when I\'m online'),
              subtitle: const Text('When this is on, people can see you\'re online and call you from your email.'),
              value: _savingOnline ?? u.showOnline,
              onChanged: _savingOnline != null ? null : _setShowOnline,
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Blocked addresses'),
              subtitle: const Text('Their emails go to Spam, and they can\'t call you.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _BlockedPage())),
            ),
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openLegalPage(context, 'privacy.html'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of Service'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openLegalPage(context, 'terms.html'),
            ),

            // ⑤ security
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
                '• Formatted emails open in a locked view, so scripts inside an email can\'t run.',
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

            // ⑦ delete account
            const _Section('Delete account'),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: AppColors.error),
              title: Text('Delete my account', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
              subtitle: const Text('Deletes your emails, domains and photo for good'),
              onTap: _deleteAccount,
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


/// Delete account: password + typing DELETE, then everything is removed for good.
class _DeleteAccountPage extends StatefulWidget {
  const _DeleteAccountPage();

  @override
  State<_DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<_DeleteAccountPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _ready => _password.text.isNotEmpty && _confirm.text.trim().toUpperCase() == 'DELETE';

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final remaining = await ApiClient.instance.deleteAccount(_password.text);
      if (mounted) Navigator.pop(context, remaining);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'This can\'t be undone. All your emails, attachments, domains, addresses and your photo '
              'will be deleted, and your address can\'t be used again. People you\'ve emailed keep their own copies.',
              style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
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
            _field('Your password', _password, secret: true),
            _field('Type DELETE to confirm', _confirm, hint: 'DELETE'),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: _busy || !_ready ? null : _delete,
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Delete account forever'),
            ),
          ],
        ),
      ),
    );
  }
}


/// The "online" dot next to "Show when I'm online": filled green when on.
class _OnlineDot extends StatelessWidget {
  final bool on;
  const _OnlineDot({required this.on});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AppColors.success : Colors.transparent,
            border: Border.all(color: on ? AppColors.success : AppColors.faint, width: 2),
            boxShadow: on
                ? [BoxShadow(color: AppColors.success.withValues(alpha: 0.35), blurRadius: 6, spreadRadius: 1)]
                : null,
          ),
        ),
      ),
    );
  }
}


/// Settings → Blocked addresses: see, unblock and add blocked senders.
class _BlockedPage extends StatefulWidget {
  const _BlockedPage();

  @override
  State<_BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<_BlockedPage> {
  final _api = ApiClient.instance;
  final _emailCtrl = TextEditingController();
  List<String>? _list;
  String? _error;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _api.blockedAddresses();
      if (mounted) setState(() => _list = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _adding = true);
    try {
      await _api.blockAddress(email);
      _emailCtrl.clear();
      _snack('$email is blocked.');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _unblock(String email) async {
    try {
      await _api.unblockAddress(email);
      _snack('$email is unblocked.');
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked addresses', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Emails from these addresses go straight to Spam, and they can\'t call you.',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(hintText: 'name@example.com'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _adding ? null : _add, child: const Text('Block')),
            ],
          ),
          const SizedBox(height: 18),
          if (_error != null)
            Text(_error!, style: TextStyle(color: AppColors.error))
          else if (list == null)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppColors.primary),
            ))
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('You haven\'t blocked anyone.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            )
          else
            for (final email in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.block, color: AppColors.muted),
                title: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(onPressed: () => _unblock(email), child: const Text('Unblock')),
              ),
        ],
      ),
    );
  }
}
