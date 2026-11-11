// inbox_screen.dart — wireframes A5 · Inbox  and  A6 · Folders drawer
// Uses the REAL server:
//   GET   /api/messages?folder=…&page=…   → the list (20 per page)
//   GET   /api/messages/counts            → numbers next to folders
//   PATCH /api/messages/<id>  {action}    → star / unstar / trash / restore
//
//   ☰  (top left)         → A6 folders drawer
//   🔍 (top right)         → A9 Search      (later)
//   avatar (top right)     → Settings tab
//   tap a message          → A7 Read        (route '/read', next step)
//   swipe a message left   → Move to trash (with Undo)
//   pull down              → refresh
//   Compose button         → A8 Compose     (route '/compose', later)

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../theme.dart';

/// The six folders, in the same order as the website sidebar.
class Folder {
  final String id;
  final String name;
  final IconData icon;
  final String emptyText;
  const Folder(this.id, this.name, this.icon, this.emptyText);
}

const folders = [
  Folder('inbox', 'Inbox', Icons.inbox_outlined, 'Your inbox is empty'),
  Folder('starred', 'Starred', Icons.star_border, 'No starred messages'),
  Folder('sent', 'Sent', Icons.send_outlined, 'Nothing sent yet'),
  Folder('drafts', 'Drafts', Icons.drafts_outlined, 'No drafts'),
  Folder('spam', 'Spam', Icons.report_gmailerrorred_outlined, 'No spam — nice!'),
  Folder('trash', 'Trash', Icons.delete_outline, 'Trash is empty'),
];

class InboxScreen extends StatefulWidget {
  final User user;
  final VoidCallback onOpenSettings; // avatar + drawer "Settings"
  final VoidCallback onOpenDomains;  // drawer "My domains"

  const InboxScreen({
    super.key,
    required this.user,
    required this.onOpenSettings,
    required this.onOpenDomains,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _api = ApiClient.instance;
  final _scroll = ScrollController();

  Folder _folder = folders.first;
  List<Message> _messages = [];
  Map<String, int> _counts = {};
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;      // first page
  bool _loadingMore = false; // next pages while scrolling
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Near the bottom of the list? Load the next 20.
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ---------------- loading ----------------

  Future<void> _load() async {
    setState(() {
      _loading = _messages.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getMessages(folder: _folder.id),
        _api.getCounts(),
      ]);
      final page = results[0] as MessagePage;
      if (!mounted) return;
      setState(() {
        _messages = page.messages;
        _page = page.page;
        _hasMore = page.hasMore;
        _counts = results[1] as Map<String, int>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _api.getMessages(folder: _folder.id, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _messages.addAll(next.messages);
        _page = next.page;
        _hasMore = next.hasMore;
      });
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openFolder(Folder f) {
    Navigator.pop(context); // close the drawer
    if (f.id == _folder.id) return;
    setState(() {
      _folder = f;
      _messages = [];
    });
    _load();
  }

  // ---------------- actions ----------------

  Future<void> _toggleStar(int index) async {
    final m = _messages[index];
    setState(() => _messages[index] = m.copyWith(isStarred: !m.isStarred)); // show it straight away
    try {
      await _api.updateMessage(m.id, m.isStarred ? 'unstar' : 'star');
    } on ApiException catch (e) {
      if (mounted) setState(() => _messages[index] = m); // undo on error
      _toast(e.message);
    }
  }

  Future<void> _trash(Message m) async {
    setState(() => _messages.removeWhere((x) => x.id == m.id));
    try {
      await _api.updateMessage(m.id, 'trash');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Moved to trash'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _api.updateMessage(m.id, 'restore');
              _load();
            },
          ),
        ));
    } on ApiException catch (e) {
      _toast(e.message);
      _load();
    }
  }

  Future<void> _open(Message m) async {
    // A7 Read screen comes next. When the user comes back, refresh
    // so the message shows as read.
    await Navigator.pushNamed(context, '/read', arguments: m.id);
    if (mounted) _load();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final unread = _counts[_folder.id];

    return Scaffold(
      drawer: _FoldersDrawer(
        user: user,
        current: _folder,
        counts: _counts,
        onFolder: _openFolder,
        onDomains: () {
          Navigator.pop(context);
          widget.onOpenDomains();
        },
        onSettings: () {
          Navigator.pop(context);
          widget.onOpenSettings();
        },
      ),
      appBar: AppBar(
        title: Text(_folder.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _toast('Search is coming soon'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onOpenSettings,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brandPanel,
                child: Text(user.initials,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/compose'),
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Compose', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // ② small line under the title: "3 unread · Newest first  ·  Temporary · 12d left"
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    unread != null && unread > 0 ? '$unread unread · Newest first' : 'Newest first',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                if (user.isTemporary)
                  Text('Temporary · ${user.daysLeft}d left',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.ink));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.ink,
      onRefresh: _load,
      child: _messages.isEmpty
          // Empty state (still inside a scroll view so pull-to-refresh works)
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(_folder.icon, size: 56, color: AppColors.border),
                const SizedBox(height: 12),
                Text(_folder.emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: AppColors.muted)),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96), // room for the Compose button
              itemCount: _messages.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, i) {
                if (i >= _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: AppColors.ink)),
                  );
                }
                final m = _messages[i];
                final row = _MessageRow(
                  message: m,
                  showRecipient: _folder.id == 'sent' || _folder.id == 'drafts',
                  onTap: () => _open(m),
                  onStar: () => _toggleStar(i),
                );
                if (_folder.id == 'trash') return row; // no swipe-to-trash inside Trash
                // ④ swipe left → trash
                return Dismissible(
                  key: ValueKey(m.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: AppColors.brandPanel,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Trash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  onDismissed: (_) => _trash(m),
                  child: row,
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// ③ One message row: avatar · sender · time · subject · preview · star
// ---------------------------------------------------------------------------
class _MessageRow extends StatelessWidget {
  final Message message;
  final bool showRecipient;
  final VoidCallback onTap;
  final VoidCallback onStar;

  const _MessageRow({
    required this.message,
    required this.showRecipient,
    required this.onTap,
    required this.onStar,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    final unread = !m.isRead;
    final who = showRecipient ? 'To: ${m.to.isEmpty ? '(no recipient)' : m.to.join(', ')}' : m.from;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;

    return Material(
      color: unread ? AppColors.soft : AppColors.surface, // unread rows are shaded
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFD6D6D2),
                child: Text(_initials(showRecipient && m.to.isNotEmpty ? m.to.first : m.from),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: weight)),
                        ),
                        const SizedBox(width: 8),
                        Text(_time(m.createdAt),
                            style: TextStyle(fontSize: 12, fontWeight: weight, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: weight)),
                        ),
                        if (m.hasAttachments)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.attach_file, size: 16, color: AppColors.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(m.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: m.isStarred ? 'Unstar' : 'Star',
                onPressed: onStar,
                icon: Icon(m.isStarred ? Icons.star : Icons.star_border,
                    color: m.isStarred ? AppColors.ink : AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "sarah@fahadimtiaz.site" → "SA"
  static String _initials(String address) {
    final name = address.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (name.isEmpty) return '?';
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// today → 10:42 · yesterday → Yesterday · this week → Mon · older → 3 Nov
  static String _time(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]}';
  }
}

// ---------------------------------------------------------------------------
// A6 · Folders drawer (slides in from the left)
// ---------------------------------------------------------------------------
class _FoldersDrawer extends StatelessWidget {
  final User user;
  final Folder current;
  final Map<String, int> counts;
  final ValueChanged<Folder> onFolder;
  final VoidCallback onDomains;
  final VoidCallback onSettings;

  const _FoldersDrawer({
    required this.user,
    required this.current,
    required this.counts,
    required this.onFolder,
    required this.onDomains,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
          children: [
            // ① account header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.brandPanel,
                    child: Text(user.initials,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(user.email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ② six folders with counts
            for (final f in folders)
              _DrawerItem(
                icon: f.icon,
                label: f.name,
                count: counts[f.id],
                selected: f.id == current.id,
                onTap: () => onFolder(f),
              ),

            // ③ Manage
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text('MANAGE',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.muted)),
            ),
            _DrawerItem(icon: Icons.language, label: 'My domains', onTap: onDomains),
            _DrawerItem(icon: Icons.settings_outlined, label: 'Settings', onTap: onSettings),

            // ④ countdown card for temporary accounts
            if (user.isTemporary) ...[
              const SizedBox(height: 20),
              _TemporaryCard(user: user),
            ],
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        leading: Icon(icon, color: AppColors.ink),
        title: Text(label,
            style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        trailing: (count != null && count! > 0)
            ? Text('$count', style: const TextStyle(fontWeight: FontWeight.w700))
            : null,
        selected: selected,
        selectedTileColor: AppColors.selected,
        selectedColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        onTap: onTap,
      ),
    );
  }
}

class _TemporaryCard extends StatelessWidget {
  final User user;
  const _TemporaryCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final totalDays = user.accountType == 'temp30' ? 30 : 15;
    final left = user.daysLeft ?? 0;
    final usedFraction = (1 - left / totalDays).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Temporary account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('$left days left', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: usedFraction,
              minHeight: 6,
              color: AppColors.ink,
              backgroundColor: const Color(0xFFDCDCD8),
            ),
          ),
        ],
      ),
    );
  }
}
