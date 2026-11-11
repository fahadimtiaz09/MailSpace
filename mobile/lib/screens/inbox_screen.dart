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
import '../widgets/brand.dart';
import '../widgets/message_row.dart';
import 'search_screen.dart';

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
    // Drafts open in Compose so they can be finished; everything else in A7 Read.
    final result = m.folder == 'drafts'
        ? await Navigator.pushNamed(context, '/compose', arguments: {'mode': 'draft', 'message': m})
        : await Navigator.pushNamed(context, '/read', arguments: m.id);
    if (result is String) _toast(result); // e.g. "Message sent"
    if (mounted) _load(); // refresh so read / moved messages update
  }

  Future<void> _compose() async {
    final result = await Navigator.pushNamed(context, '/compose');
    if (result is String) _toast(result);
    if (mounted) _load();
  }

  Future<void> _search() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SearchScreen(folder: _folder.id, folderName: _folder.name)),
    );
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
            onPressed: _search,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onOpenSettings,
              child: Avatar(seed: user.email, text: user.initials, radius: 18),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: AppColors.primaryBtn,
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
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                if (user.isTemporary)
                  Text('Temporary · ${user.daysLeft}d left',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
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
                    style: TextStyle(fontSize: 16, color: AppColors.muted)),
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
                  return Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  );
                }
                final m = _messages[i];
                final row = MessageRow(
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
                    color: AppColors.error,
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
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: BrandLockup(logoWidth: 38, fontSize: 20),
            ),
            // ① account header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  Avatar(seed: user.email, text: user.initials, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(user.email,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
            Padding(
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
        selectedColor: AppColors.primary,
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
              color: AppColors.primary,
              backgroundColor: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}
