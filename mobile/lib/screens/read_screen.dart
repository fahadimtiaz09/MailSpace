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
//   ③ body — the email's design (HTML) if it has one, otherwise plain text
//   ④ attachments → tap to open
//   ⑤ Reply · Reply all · Forward → A8 Compose (later)
//
// Protection (same rules as the website):
//   • 📞 / 🎥 call buttons — enabled only while the other person is online
//   • Forward is locked if the person who wrote it switched forwarding off
//   • copying text gives only stars (*****)
//   • Android: screenshots are blocked while an email is open
//     iPhone / Android 14+: a screenshot sends the writer an alert email

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/message.dart';
import '../services/call_service.dart';
import '../services/screen_guard.dart';
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

  // Calls: can we call the other person right now?
  String? _callTarget;
  bool _canCall = false;
  String _callTip = 'Checking if they are online…';
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    ScreenGuard.secure(true);                 // Android: block screenshots of emails
    ScreenGuard.onScreenshot = _onScreenshot; // iPhone / Android 14+: tell the sender
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    ScreenGuard.secure(false);
    if (ScreenGuard.onScreenshot == _onScreenshot) ScreenGuard.onScreenshot = null;
    super.dispose();
  }

  void _onScreenshot() {
    final m = _message;
    if (m == null) return;
    _api.reportScreenshot(m.id, ScreenGuard.platformName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screenshot detected. The sender has been notified.')),
      );
    }
  }

  // ---------------- calls ----------------

  static final _systemSender = RegExp(r'^(calls|alerts|no-?reply)@', caseSensitive: false);

  String? _targetFor(Message m) {
    final outgoing = m.folder == 'sent' || m.folder == 'drafts';
    final email = outgoing ? (m.to.isNotEmpty ? m.to.first : null) : m.from;
    if (email == null || email.isEmpty || _systemSender.hasMatch(email) || m.folder == 'trash') return null;
    return email;
  }

  void _watchPresence(Message m) {
    _callTarget = _targetFor(m);
    _presenceTimer?.cancel();
    if (_callTarget == null) return;
    _checkPresence();
    _presenceTimer = Timer.periodic(const Duration(seconds: 8), (_) => _checkPresence());
  }

  Future<void> _checkPresence() async {
    final email = _callTarget;
    if (email == null) return;
    try {
      final p = await _api.callPresence(email);
      if (!mounted || email != _callTarget) return;
      setState(() {
        _canCall = p['can_call'] == true;
        _callTip = _canCall ? 'Call' : (p['reason'] as String? ?? '$email is offline');
      });
    } catch (_) {
      if (mounted) setState(() => _canCall = false);
    }
  }

  void _call(String kind) {
    if (_callTarget != null) CallService.instance.call(_callTarget!, kind);
  }

  void _forward() {
    if (_message?.canForward == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forwarding has been disabled by the mail owner.')),
      );
      return;
    }
    _reply('forward');
  }

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
      if (mounted) _watchPresence(m);
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
                        child: _ReplyButton(
                      icon: m.canForward ? Icons.forward : Icons.lock_outline,
                      label: 'Forward',
                      onTap: _forward,
                      locked: !m.canForward,
                    )),
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
      if (_callTarget != null) ...[
        IconButton(
          tooltip: _canCall ? 'Voice call' : _callTip,
          icon: Icon(Icons.call_outlined, color: _canCall ? AppColors.success : AppColors.faint),
          onPressed: _canCall ? () => _call('audio') : null,
        ),
        IconButton(
          tooltip: _canCall ? 'Video call' : _callTip,
          icon: Icon(Icons.videocam_outlined, color: _canCall ? AppColors.success : AppColors.faint),
          onPressed: _canCall ? () => _call('video') : null,
        ),
      ],
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
        GuardedText(
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

        // ③ body — the email's design (Gmail templates) or plain text
        if ((m.bodyHtml ?? '').isNotEmpty)
          MailHtmlBody(html: m.bodyHtml!)
        else
          GuardedText(
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
  final bool locked; // forwarding switched off by the owner → looks grey
  const _ReplyButton({required this.icon, required this.label, required this.onTap, this.locked = false});

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
        foregroundColor: locked ? AppColors.faint : null,
      ),
    );
  }
}

// ---------------- Copy protection ----------------
//
// Text you can select, but "Copy" (menu or Ctrl+C) puts only stars (*****)
// on the clipboard.

class _StarCopyIntent extends Intent {
  const _StarCopyIntent();
}

class GuardedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const GuardedText(this.text, {super.key, this.style});

  static String starsFor(String selected) => '*' * selected.length.clamp(8, 2000).toInt();

  static void _copyStars(BuildContext context, String selected) {
    Clipboard.setData(ClipboardData(text: starsFor(selected)));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copying email text is not allowed.')));
  }

  @override
  Widget build(BuildContext context) {
    String selected = '';
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyC, control: true): _StarCopyIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true): _StarCopyIntent(),
        SingleActivator(LogicalKeyboardKey.keyX, control: true): _StarCopyIntent(),
      },
      child: Actions(
        actions: {
          _StarCopyIntent: CallbackAction<_StarCopyIntent>(onInvoke: (_) {
            _copyStars(context, selected);
            return null;
          }),
        },
        child: SelectableText(
          text,
          style: style,
          onSelectionChanged: (selection, _) => selected = selection.textInside(text),
          contextMenuBuilder: (menuContext, editable) {
            final value = editable.textEditingValue;
            final picked = value.selection.textInside(value.text);
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editable.contextMenuAnchors,
              buttonItems: [
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.copy,
                  onPressed: () {
                    _copyStars(context, picked);
                    editable.hideToolbar();
                  },
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.selectAll,
                  onPressed: () => editable.selectAll(SelectionChangedCause.toolbar),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


// ---------------- Email design (HTML) ----------------
//
// The server already cleaned this HTML (no scripts, no forms...). Here:
//   • logos sent inside the email (data:image/...) are shown straight away
//   • pictures from other websites stay hidden until "Show images"
//     (they can tell the sender you opened the email — same as the website)
//   • links open in the phone's browser
// It sits on a white card, because email designs are made for a white page.

class MailHtmlBody extends StatefulWidget {
  final String html;
  const MailHtmlBody({super.key, required this.html});

  @override
  State<MailHtmlBody> createState() => _MailHtmlBodyState();
}

class _MailHtmlBodyState extends State<MailHtmlBody> {
  bool _showRemote = false;

  bool get _hasRemoteImages => RegExp(r'<img[^>]+src="https?:', caseSensitive: false).hasMatch(widget.html);

  Future<bool> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto')) {
      return true; // anything else is ignored
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
    return true;
  }

  double? _size(String? v) => double.tryParse((v ?? '').replaceAll('px', '').trim());

  /// Draws every <img> ourselves so we decide what loads.
  Widget? _image(dynamic element) {
    if (element.localName != 'img') return null;
    final String src = (element.attributes['src'] ?? '').toString();
    final w = _size(element.attributes['width']);
    final h = _size(element.attributes['height']);
    Widget child;

    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.substring(src.indexOf(',') + 1).replaceAll(RegExp(r'\s'), ''));
        child = Image.memory(bytes, width: w, height: h, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
      } catch (_) {
        return InlineCustomWidget(child: const SizedBox.shrink());
      }
    } else if (src.startsWith('http://') || src.startsWith('https://')) {
      if (!_showRemote) {
        child = Container(
          width: w ?? 24,
          height: h ?? 24,
          color: const Color(0xFFF1F3F4),
          child: const Icon(Icons.image_outlined, size: 16, color: Color(0xFF9AA0A6)),
        );
      } else {
        child = Image.network(src, width: w, height: h, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
      }
    } else {
      return InlineCustomWidget(child: const SizedBox.shrink());
    }
    return InlineCustomWidget(
      child: LayoutBuilder(
        builder: (context, box) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth.isFinite ? box.maxWidth : 600),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasRemoteImages && !_showRemote)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.image_not_supported_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Images are hidden to protect your privacy.',
                      style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ),
                TextButton(
                  onPressed: () => setState(() => _showRemote = true),
                  child: const Text('Show images'),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, // email designs expect a white page (Gmail does the same)
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: HtmlWidget(
            widget.html,
            key: ValueKey(_showRemote), // redraw after "Show images"
            textStyle: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF202124)),
            customWidgetBuilder: _image,
            onTapUrl: _openLink,
          ),
        ),
      ],
    );
  }
}