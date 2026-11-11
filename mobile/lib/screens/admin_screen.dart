// admin_screen.dart — Admin console (same as the website's admin.html).
// Only for admin accounts; opened from the drawer or Settings.
// Uses backend/routes/admin.py:
//   GET  /api/admin/stats                    → Overview numbers
//   GET  /api/admin/users?q=&page=           → Users
//   GET  /api/admin/messages?q=&flagged=1&user_id=&page=  → all mail (no text)
//   POST /api/admin/messages/<id>/view {reason}  → open text (LOGGED)
//   GET  /api/admin/attachments/<id>         → download file (LOGGED)
//   GET  /api/admin/audit?page=              → Audit log

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../api/api_client.dart';
import '../models/admin.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/message_row.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  // "View mail" on a user → Messages tab shows only that user's mail.
  AdminUser? _mailOf;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _viewMailOf(AdminUser u) {
    setState(() => _mailOf = u);
    _tabs.animateTo(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin console'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.primary,
          dividerColor: AppColors.border,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Users'),
            Tab(text: 'Messages'),
            Tab(text: 'Audit log'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Warning banner (same text as the website)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Admin access is logged. Open message content only for safety or policy reasons.',
                    style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const _OverviewTab(),
                _UsersTab(onViewMail: _viewMailOf),
                _MessagesTab(
                  key: ValueKey(_mailOf?.id), // reload when the user filter changes
                  mailOf: _mailOf,
                  onClearUser: () => setState(() => _mailOf = null),
                ),
                const _AuditTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------
class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> with AutomaticKeepAliveClientMixin {
  AdminStats? _stats;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ApiClient.instance.getAdminStats();
      if (mounted) setState(() => _stats = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorView(text: _error!, onRetry: () {
      setState(() => _error = null);
      _load();
    });
    final s = _stats;
    if (s == null) return const Center(child: CircularProgressIndicator());

    final tiles = [
      ('Users', s.users, Icons.people_outline, AppColors.primary),
      ('Admins', s.admins, Icons.admin_panel_settings_outlined, AppColors.primary),
      ('Temporary accounts', s.temporary, Icons.timer_outlined, AppColors.warning),
      ('Messages', s.messages, Icons.mail_outline, AppColors.primary),
      ('Verified domains', s.domains, Icons.language, AppColors.success),
      ('Domain addresses', s.addresses, Icons.alternate_email, AppColors.success),
      ('Reviews (logged)', s.reviews, Icons.history, AppColors.muted),
      ('Flagged messages', s.flagged, Icons.flag_outlined, AppColors.error),
    ];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 104,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: tiles.length,
        itemBuilder: (context, i) {
          final (label, value, icon, color) = tiles[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const Spacer(),
                Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted), maxLines: 1),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------
class _UsersTab extends StatefulWidget {
  final ValueChanged<AdminUser> onViewMail;
  const _UsersTab({required this.onViewMail});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  List<AdminUser> _rows = [];
  int _page = 1, _total = 0;
  bool _hasMore = false, _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await ApiClient.instance.getAdminUsers(page: reset ? 1 : _page + 1, q: _search.text);
      if (!mounted) return;
      setState(() {
        _rows = reset ? p.items : [..._rows, ...p.items];
        _page = p.page;
        _hasMore = p.hasMore;
        _total = p.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBox(
          controller: _search,
          hint: 'Search username or email…',
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
          },
        ),
        if (_error != null) Expanded(child: _ErrorView(text: _error!, onRetry: () => _load(reset: true))),
        if (_error == null)
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: _rows.length + 2,
                itemBuilder: (context, i) {
                  if (i == 0) return _CountLine(text: _loading && _rows.isEmpty ? 'Loading…' : '$_total users');
                  if (i == _rows.length + 1) {
                    return _MoreButton(loading: _loading, hasMore: _hasMore, onTap: () => _load());
                  }
                  final u = _rows[i - 1];
                  return _UserCard(user: u, onViewMail: () => widget.onViewMail(u));
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final AdminUser user;
  final VoidCallback onViewMail;
  const _UserCard({required this.user, required this.onViewMail});

  @override
  Widget build(BuildContext context) {
    final u = user;
    final type = switch (u.accountType) {
      'temp15' => 'Temporary · 15 days',
      'temp30' => 'Temporary · 30 days',
      _ => 'Regular',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(seed: u.email, text: MessageRow.initialsOf(u.email), radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(u.username,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                        if (u.role == 'admin') ...[
                          const SizedBox(width: 6),
                          _Badge(text: 'Admin', fg: AppColors.primary, bg: AppColors.primarySoft),
                        ],
                        if (u.status != 'active') ...[
                          const SizedBox(width: 6),
                          _Badge(text: u.status, fg: AppColors.errorText, bg: AppColors.errorSoft),
                        ],
                      ],
                    ),
                    Text(u.email,
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Meta(icon: Icons.badge_outlined, text: type),
              _Meta(icon: Icons.inbox_outlined, text: '${u.inboxCount} in inbox'),
              _Meta(icon: Icons.event_outlined, text: 'Joined ${MessageRow.fullTime(u.createdAt).split(',').first}'),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onViewMail,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('View mail'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Messages (all mail — subject only, text needs a reason)
// ---------------------------------------------------------------------------
class _MessagesTab extends StatefulWidget {
  final AdminUser? mailOf;
  final VoidCallback onClearUser;
  const _MessagesTab({super.key, required this.mailOf, required this.onClearUser});

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _flaggedOnly = false;
  List<AdminMessage> _rows = [];
  int _page = 1, _total = 0;
  bool _hasMore = false, _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await ApiClient.instance.getAdminMessages(
        page: reset ? 1 : _page + 1,
        q: _search.text,
        userId: widget.mailOf?.id,
        flaggedOnly: _flaggedOnly,
      );
      if (!mounted) return;
      setState(() {
        _rows = reset ? p.items : [..._rows, ...p.items];
        _page = p.page;
        _hasMore = p.hasMore;
        _total = p.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Asks for a reason, then opens the message (the server logs it).
  Future<void> _open(AdminMessage m) async {
    final reason = await showDialog<String>(context: context, builder: (context) => _ReasonDialog(message: m));
    if (reason == null || !mounted) return;
    try {
      final full = await ApiClient.instance.adminOpenMessage(m.id, reason);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (context) => _AdminMessagePage(message: full)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBox(
          controller: _search,
          hint: 'Search sender, recipient or subject…',
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilterChip(
                label: const Text('Flagged only'),
                avatar: Icon(Icons.flag_outlined, size: 18, color: AppColors.error),
                selected: _flaggedOnly,
                onSelected: (v) {
                  setState(() => _flaggedOnly = v);
                  _load(reset: true);
                },
              ),
              if (widget.mailOf != null)
                InputChip(
                  label: Text('Mail of ${widget.mailOf!.username}'),
                  onDeleted: widget.onClearUser,
                ),
            ],
          ),
        ),
        if (_error != null) Expanded(child: _ErrorView(text: _error!, onRetry: () => _load(reset: true))),
        if (_error == null)
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: _rows.length + 2,
                itemBuilder: (context, i) {
                  if (i == 0) return _CountLine(text: _loading && _rows.isEmpty ? 'Loading…' : '$_total messages');
                  if (i == _rows.length + 1) {
                    return _MoreButton(loading: _loading, hasMore: _hasMore, onTap: () => _load());
                  }
                  final m = _rows[i - 1];
                  return _AdminMessageCard(message: m, onOpen: () => _open(m));
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminMessageCard extends StatelessWidget {
  final AdminMessage message;
  final VoidCallback onOpen;
  const _AdminMessageCard({required this.message, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: m.flagged ? AppColors.error : AppColors.border, width: m.flagged ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(seed: m.from, text: MessageRow.initialsOf(m.from), radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(m.from,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  Text(MessageRow.shortTime(m.createdAt), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
              const SizedBox(height: 6),
              Text('to ${m.to.join(', ')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (m.flagged)
                    _Badge(
                      text: m.flagWords.isEmpty ? 'Flagged' : 'Flagged: ${m.flagWords.join(', ')}',
                      fg: AppColors.errorText,
                      bg: AppColors.errorSoft,
                    ),
                  if (m.external) _Badge(text: 'External', fg: AppColors.warning, bg: AppColors.warningSoft),
                  if (m.hasAttachments)
                    _Badge(
                      text: '${m.attachments.length} attachment${m.attachments.length == 1 ? '' : 's'}',
                      fg: AppColors.muted,
                      bg: AppColors.bg2,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.faint),
                  const SizedBox(width: 4),
                  Text('Text hidden · tap to open with a reason',
                      style: TextStyle(fontSize: 12, color: AppColors.faint)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Open message content" — the reason is saved in the audit log.
class _ReasonDialog extends StatefulWidget {
  final AdminMessage message;
  const _ReasonDialog({required this.message});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return AlertDialog(
      title: const Text('Open message content'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: ${m.from}', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            Text('Subject: ${m.subject.isEmpty ? '(no subject)' : m.subject}',
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
            Text('Date: ${MessageRow.fullTime(m.createdAt)}', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Please type a short reason.',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            if (_ctrl.text.trim().length < 3) {
              setState(() => _error = 'Please give a short reason (at least 3 characters).');
              return;
            }
            Navigator.pop(context, _ctrl.text.trim());
          },
          child: const Text('Open and log'),
        ),
      ],
    );
  }
}

/// The opened message (read-only), with logged attachment downloads.
class _AdminMessagePage extends StatefulWidget {
  final AdminMessage message;
  const _AdminMessagePage({required this.message});

  @override
  State<_AdminMessagePage> createState() => _AdminMessagePageState();
}

class _AdminMessagePageState extends State<_AdminMessagePage> {
  String? _downloading;

  Future<void> _download(AdminAttachment a) async {
    if (a.id == null) return;
    setState(() => _downloading = a.id);
    try {
      final path = await ApiClient.instance.adminDownloadAttachment(a);
      await OpenFilex.open(path);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Scaffold(
      appBar: AppBar(title: const Text('Message (admin view)')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(10)),
            child: Text('This view was recorded in the audit log.',
                style: TextStyle(fontSize: 12, color: AppColors.ink)),
          ),
          const SizedBox(height: 14),
          SelectableText(m.subject.isEmpty ? '(no subject)' : m.subject,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 12),
          Row(
            children: [
              Avatar(seed: m.from, text: MessageRow.initialsOf(m.from), radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.from, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    Text('to ${m.to.join(', ')}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Text(MessageRow.fullTime(m.createdAt), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 18),
          SelectableText((m.body ?? '').isEmpty ? '(This message has no text.)' : m.body!,
              style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink)),
          if (m.attachments.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (final a in m.attachments)
              Card(
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file_outlined, color: AppColors.primary),
                  title: Text(a.filename, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Download is logged'),
                  trailing: _downloading == a.id
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  onTap: _downloading == null ? () => _download(a) : null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------
class _AuditTab extends StatefulWidget {
  const _AuditTab();

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> with AutomaticKeepAliveClientMixin {
  List<AuditEntry> _rows = [];
  int _page = 1, _total = 0;
  bool _hasMore = false, _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await ApiClient.instance.getAuditLog(page: reset ? 1 : _page + 1);
      if (!mounted) return;
      setState(() {
        _rows = reset ? p.items : [..._rows, ...p.items];
        _page = p.page;
        _hasMore = p.hasMore;
        _total = p.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorView(text: _error!, onRetry: () => _load(reset: true));
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _rows.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _CountLine(text: _loading && _rows.isEmpty ? 'Loading…' : '$_total entries');
          if (i == _rows.length + 1) return _MoreButton(loading: _loading, hasMore: _hasMore, onTap: () => _load());
          final r = _rows[i - 1];
          final isFile = r.action == 'download_attachment';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(isFile ? Icons.download_outlined : Icons.visibility_outlined,
                      size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(r.actionText,
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                          ),
                          Text(MessageRow.shortTime(r.createdAt),
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${r.adminEmail} → ${r.targetEmail}',
                          style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      if (r.reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('“${r.reason}”', style: TextStyle(fontSize: 13, color: AppColors.ink)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------
class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchBox({required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(Icons.search, color: AppColors.muted),
            isDense: true,
          ),
        ),
      );
}

class _CountLine extends StatelessWidget {
  final String text;
  const _CountLine({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.muted)),
      );
}

class _MoreButton extends StatelessWidget {
  final bool loading, hasMore;
  final VoidCallback onTap;
  const _MoreButton({required this.loading, required this.hasMore, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    if (!hasMore) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton(onPressed: onTap, child: const Text('Load more')),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color fg, bg;
  const _Badge({required this.text, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      );
}

class _ErrorView extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _ErrorView({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
