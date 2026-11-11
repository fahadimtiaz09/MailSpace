// read_screen.dart — wireframe A7 · Read message
// Opened from the Inbox with the message id:
//   Navigator.pushNamed(context, '/read', arguments: message.id)
//
// Uses the REAL server:
//   GET   /api/messages/<id>          → subject, body, attachments (also marks it read)
//   PATCH /api/messages/<id> {action} → trash / spam / unread / star / restore / delete_forever
//   GET   /api/attachments/<id>       → download a file
//
//   ① top: back · trash · spam · mark unread · star   (in Trash: restore · delete forever)
//   ② subject, sender, time
//   ③ plain-text body
//   ④ attachments → tap to open
//   ⑤ Reply · Reply all · Forward → A8 Compose (later)

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../api/api_client.dart';
import '../models/message.dart';
import '../theme.dart';
import '../widgets/brand.dart';

class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key});

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  final _api = ApiClient.instance;

  Message? _message;
  String? _error;
  bool _busy = false;            // while an action (trash, star…) is running
  String? _downloadingId;        // attachment being downloaded

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_message == null && _error == null) _load();
  }

  Future<void> _load() async {
    final id = ModalRoute.of(context)!.settings.arguments as String;
    try {
      final m = await _api.getMessage(id);
      if (mounted) setState(() => _message = m);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Runs an action. If [close] is true, go back to the list afterwards
  /// (trash, spam, restore, delete forever, mark unread).
  Future<void> _action(String action, String doneText, {bool close = true}) async {
    final m = _message!;
    setState(() => _busy = true);
    try {
      await _api.updateMessage(m.id, action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneText)));
      if (close) {
        Navigator.pop(context, true);
      } else if (action == 'star' || action == 'unstar') {
        setState(() => _message = m.copyWith(isStarred: action == 'star'));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteForever() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This message will be removed permanently. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (yes == true) _action('delete_forever', 'Deleted forever');
  }

  Future<void> _openAttachment(Attachment a) async {
    setState(() => _downloadingId = a.id);
    try {
      final path = await _api.downloadAttachment(a);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app on this phone can open this file.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _reply(String mode) async {
    // A8 Compose reads these arguments to fill in To, Subject and the quoted text.
    final result = await Navigator.pushNamed(context, '/compose', arguments: {'mode': mode, 'message': _message});
    // Sent? Go back to the list and let it show "Message sent".
    if (result is String && mounted) Navigator.pop(context, result);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final m = _message;

    return Scaffold(
      appBar: AppBar(
        actions: m == null ? null : _topActions(m),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.error)),
              ),
            )
          : m == null
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _content(m),
      // ⑤ Reply · Reply all · Forward
      bottomNavigationBar: m == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 1.5))),
                child: Row(
                  children: [
                    Expanded(child: _ReplyButton(icon: Icons.reply, label: 'Reply', onTap: () => _reply('reply'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _ReplyButton(icon: Icons.reply_all, label: 'Reply all', onTap: () => _reply('reply_all'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _ReplyButton(icon: Icons.forward, label: 'Forward', onTap: () => _reply('forward'))),
                  ],
                ),
              ),
            ),
    );
  }

  // ① icons in the top bar — different inside Trash
  List<Widget> _topActions(Message m) {
    if (m.folder == 'trash') {
      return [
        IconButton(
          tooltip: 'Restore',
          icon: const Icon(Icons.restore_from_trash_outlined),
          onPressed: _busy ? null : () => _action('restore', 'Message restored'),
        ),
        IconButton(
          tooltip: 'Delete forever',
          icon: Icon(Icons.delete_forever_outlined, color: AppColors.error),
          onPressed: _busy ? null : _confirmDeleteForever,
        ),
        const SizedBox(width: 4),
      ];
    }
    return [
      IconButton(
        tooltip: 'Move to trash',
        icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => _action('trash', 'Moved to trash'),
      ),
      if (m.folder == 'inbox')
        IconButton(
          tooltip: 'Report spam',
          icon: const Icon(Icons.report_gmailerrorred_outlined),
          onPressed: _busy ? null : () => _action('spam', 'Moved to spam'),
        ),
      if (m.folder == 'spam')
        IconButton(
          tooltip: 'Not spam',
          icon: const Icon(Icons.move_to_inbox_outlined),
          onPressed: _busy ? null : () => _action('not_spam', 'Moved to inbox'),
        ),
      IconButton(
        tooltip: 'Mark as unread',
        icon: const Icon(Icons.mark_email_unread_outlined),
        onPressed: _busy ? null : () => _action('unread', 'Marked as unread'),
      ),
      IconButton(
        tooltip: m.isStarred ? 'Unstar' : 'Star',
        icon: Icon(m.isStarred ? Icons.star : Icons.star_border),
        onPressed: _busy
            ? null
            : () => _action(m.isStarred ? 'unstar' : 'star', m.isStarred ? 'Star removed' : 'Starred', close: false),
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _content(Message m) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // ② subject
        SelectableText(
          m.subject.isEmpty ? '(no subject)' : m.subject,
          style: TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 16),

        // sender row
        Row(
          children: [
            Avatar(seed: m.from, text: _initials(m.from), radius: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.from,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('to ${m.to.join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_fullTime(m.createdAt), style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 20),

        // ③ body — plain text only (same safety rule as the website)
        SelectableText(
          (m.body ?? '').isEmpty ? '(This message has no text.)' : m.body!,
          style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink),
        ),

        // ④ attachments
        if (m.attachments.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('${m.attachments.length} attachment${m.attachments.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 8),
          for (final a in m.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _downloadingId == null ? () => _openAttachment(a) : null,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(_fileIcon(a.filename), size: 30, color: AppColors.ink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${_size(a.size)} · tap to open',
                                style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      if (_downloadingId == a.id)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      else
                        Icon(Icons.download_outlined, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------- small helpers ----------------

  static String _initials(String address) {
    final name = address.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (name.isEmpty) return '?';
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// "11 Nov, 10:42"
  static String _fullTime(DateTime? t) {
    if (t == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]}, $hh:$mm';
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  static IconData _fileIcon(String name) {
    final ext = name.toLowerCase().split('.').last;
    if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) return Icons.image_outlined;
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    return Icons.description_outlined;
  }
}

class _ReplyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ReplyButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
