// compose_screen.dart — wireframe A8 · Compose
// Full screen on a phone. Opened in 5 ways (route '/compose'):
//   nothing                                  → new message
//   {'mode': 'reply',     'message': m}      → To = sender, "Re: subject", quoted text
//   {'mode': 'reply_all', 'message': m}      → To = everyone except me
//   {'mode': 'forward',   'message': m}      → "Fwd: subject", forwarded text
//   {'mode': 'draft',     'message': m}      → continue a saved draft
//
// Uses the REAL server:
//   GET  /api/domains/from-addresses  → From dropdown
//   POST /api/messages/send           → send (multipart, with files)
//   POST /api/drafts                  → save draft (files are not saved)
//
// When sent, the screen closes and returns "Message sent" so the list
// can show it at the bottom.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/message.dart';
import '../theme.dart';
import '../widgets/message_row.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const maxFiles = 5;
  static const maxFileSize = 10 * 1024 * 1024; // 10 MB
  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx', 'txt'];

  final _api = ApiClient.instance;
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _mode = 'new';
  String? _draftId;
  List<String> _fromAddresses = [];
  String? _from;
  final List<UploadFile> _files = [];
  bool _allowForward = true; // "Allow forwarding" switch
  String? _forwardOf;        // the email being forwarded (server checks the owner allowed it)

  bool _started = false;
  bool _sending = false;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _setUp();
    }
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ---------------- set up (From list + reply / forward / draft) ----------------

  Future<void> _setUp() async {
    final args = ModalRoute.of(context)!.settings.arguments;
    Message? original;
    if (args is Map) {
      _mode = args['mode'] as String? ?? 'new';
      original = args['message'] as Message?;
    }

    try {
      final from = await _api.getFromAddresses();
      if (!mounted) return;
      setState(() {
        _fromAddresses = from;
        _from = from.isNotEmpty ? from.first : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }

    if (original == null) return;

    // The list item has no body — load the full message for quoting / drafts.
    Message full = original;
    if (original.body == null) {
      try {
        full = await _api.getMessage(original.id);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
        return;
      }
    }
    if (!mounted) return;

    final mine = _fromAddresses.map((e) => e.toLowerCase()).toSet();
    final subject = full.subject;
    // Forwarding switched off by the owner → don't copy their text into a reply
    final quoted = full.canForward
        ? (full.body ?? '').split('\n').map((line) => '> $line').join('\n')
        : '';

    setState(() {
      switch (_mode) {
        case 'reply':
          _toCtrl.text = full.from;
          _subjectCtrl.text = _prefix('Re: ', subject);
          _bodyCtrl.text = '\n\nOn ${MessageRow.fullTime(full.createdAt)}, ${full.from} wrote:\n$quoted';
          // Reply from the address the mail was sent to, if it is one of mine.
          final toMe = full.to.firstWhere((t) => mine.contains(t.toLowerCase()), orElse: () => '');
          if (toMe.isNotEmpty) _from = _fromAddresses.firstWhere((a) => a.toLowerCase() == toMe.toLowerCase());
          break;
        case 'reply_all':
          final everyone = <String>[full.from, ...full.to]
              .where((a) => !mine.contains(a.toLowerCase()))
              .toSet()
              .toList();
          _toCtrl.text = everyone.join(', ');
          _subjectCtrl.text = _prefix('Re: ', subject);
          _bodyCtrl.text = '\n\nOn ${MessageRow.fullTime(full.createdAt)}, ${full.from} wrote:\n$quoted';
          break;
        case 'forward':
          _forwardOf = full.id;
          _subjectCtrl.text = _prefix('Fwd: ', subject);
          _bodyCtrl.text = '\n\n---------- Forwarded message ----------\n'
              'From: ${full.from}\n'
              'Date: ${MessageRow.fullTime(full.createdAt)}\n'
              'Subject: $subject\n'
              'To: ${full.to.join(', ')}\n\n'
              '${full.body ?? ''}';
          break;
        case 'draft':
          _draftId = full.id;
          _toCtrl.text = full.to.join(', ');
          _subjectCtrl.text = subject;
          _bodyCtrl.text = full.body ?? '';
          break;
      }
    });
  }

  static String _prefix(String p, String subject) =>
      subject.toLowerCase().startsWith(p.toLowerCase()) ? subject : '$p$subject';

  String get _title => switch (_mode) {
        'reply' || 'reply_all' => 'Reply',
        'forward' => 'Forward',
        'draft' => 'Draft',
        _ => 'New message',
      };

  bool get _hasContent =>
      _toCtrl.text.trim().isNotEmpty || _subjectCtrl.text.trim().isNotEmpty || _bodyCtrl.text.trim().isNotEmpty;

  // ---------------- attachments ----------------

  Future<void> _pickFiles() async {
    if (_files.length >= maxFiles) {
      setState(() => _error = 'You can attach up to $maxFiles files.');
      return;
    }
    final List<PlatformFile>? picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (picked == null || !mounted) return;

    String? problem;
    setState(() {
      for (final f in picked) {
        if (f.path == null) continue;
        if (_files.length >= maxFiles) {
          problem = 'You can attach up to $maxFiles files.';
          break;
        }
        // Read the size from the file itself (works with every file_picker version).
        final size = File(f.path!).lengthSync();
        if (size > maxFileSize) {
          problem = '${f.name} is bigger than 10 MB.';
          continue;
        }
        _files.add(UploadFile(path: f.path!, name: f.name, size: size));
      }
      _error = problem;
    });
  }

  // ---------------- send / draft / close ----------------

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (_toCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Add at least one recipient.');
      return;
    }
    if (_from == null) {
      setState(() => _error = 'Could not load your addresses. Close and try again.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = await _api.sendMessage(
        from: _from!,
        to: _toCtrl.text,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
        files: _files,
        draftId: _draftId,
        allowForward: _allowForward,
        forwardOf: _forwardOf,
      );
      if (mounted) Navigator.pop(context, message); // e.g. "Message sent"
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _saveDraft() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _draftId = await _api.saveDraft(
        to: _toCtrl.text,
        subject: _subjectCtrl.text,
        body: _bodyCtrl.text,
        draftId: _draftId,
      );
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDraftAndClose() async {
    if (await _saveDraft() && mounted) {
      Navigator.pop(context, _files.isEmpty ? 'Draft saved' : 'Draft saved (attachments aren\'t saved in drafts)');
    }
  }

  /// × button / phone back button: ask what to do if something was typed.
  Future<void> _close() async {
    if (!_hasContent) {
      Navigator.pop(context);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as draft?'),
        content: const Text('You can finish this message later from Drafts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save draft')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') Navigator.pop(context);
    if (choice == 'save') _saveDraftAndClose();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _saving;

    return PopScope(
      canPop: false, // we decide (Save as draft?) in _close()
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: busy ? null : _close),
          title: Text(_title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Attach files',
              icon: const Icon(Icons.attach_file),
              onPressed: busy ? null : _pickFiles,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton(
                onPressed: busy ? null : _send,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(84, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Send'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Error box
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    border: Border.all(color: AppColors.error, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 14)),
                ),

              // From
              _FieldRow(
                label: 'From',
                child: _fromAddresses.isEmpty
                    ? Text('Loading…', style: TextStyle(color: AppColors.muted))
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _from,
                          isExpanded: true,
                          items: [
                            for (final a in _fromAddresses)
                              DropdownMenuItem(value: a, child: Text(a, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: busy ? null : (v) => setState(() => _from = v),
                        ),
                      ),
              ),
              // To
              _FieldRow(
                label: 'To',
                child: TextField(
                  controller: _toCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _plain('name@gmail.com, friend@fahadimtiaz.site'),
                ),
              ),
              // Subject
              _FieldRow(
                label: 'Subject',
                child: TextField(
                  controller: _subjectCtrl,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _plain('').copyWith(counterText: ''),
                ),
              ),

              // Body (fills the rest of the screen)
              Expanded(
                child: TextField(
                  controller: _bodyCtrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                  decoration: _plain('Write your message…').copyWith(
                    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  ),
                ),
              ),

              // Attachment chips
              if (_files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in _files)
                        InputChip(
                          avatar: const Icon(Icons.insert_drive_file_outlined, size: 18),
                          label: Text('${f.name} · ${_size(f.size)}', overflow: TextOverflow.ellipsis),
                          onDeleted: busy ? null : () => setState(() => _files.remove(f)),
                          deleteButtonTooltipMessage: 'Remove ${f.name}',
                        ),
                    ],
                  ),
                ),

              // Allow forwarding switch
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 1.5))),
                child: Row(
                  children: [
                    Icon(_allowForward ? Icons.forward : Icons.lock_outline, size: 18, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _allowForward ? 'Allow forwarding' : 'Forwarding off — people can\'t forward this email',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ),
                    Switch(
                      value: _allowForward,
                      onChanged: busy ? null : (v) => setState(() => _allowForward = v),
                    ),
                  ],
                ),
              ),

              // Bottom row: hint · Save draft · Discard
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 1.5))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Up to 5 files, 10 MB each', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                    TextButton(
                      onPressed: busy ? null : _saveDraftAndClose,
                      child: _saving
                          ? SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                          : const Text('Save draft'),
                    ),
                    IconButton(
                      tooltip: 'Discard',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: busy ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Text box without a border (Compose rows use lines instead).
  static InputDecoration _plain(String hint) => InputDecoration(
        hintText: hint,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      );

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}

/// One line in Compose: grey label on the left, field on the right, line below.
class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5))),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
