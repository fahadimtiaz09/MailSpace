// search_screen.dart — wireframe A9 · Search
// Opens from the 🔍 icon on the Inbox. Keyboard opens straight away.
// Uses GET /api/messages?folder=…&q=…  (the same list API, with search text).
//
//   ① search box: ← closes, × clears. Results update while typing
//      (after a short pause, so the server isn't called on every key).
//   ② chips: current folder / All folders
//   ③ results — same rows as the Inbox; tap → A7 Read
//   ④ "No matches" when nothing is found

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/message.dart';
import '../theme.dart';
import '../widgets/message_row.dart';

class SearchScreen extends StatefulWidget {
  final String folder;     // folder the user was in, e.g. 'inbox'
  final String folderName; // 'Inbox'

  const SearchScreen({super.key, required this.folder, required this.folderName});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  bool _allFolders = false;
  List<Message> _results = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onTyping(String text) {
    setState(() {}); // show / hide the × button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    _lastQuery = q;
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _total = 0;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ApiClient.instance.getMessages(folder: _allFolders ? 'all' : widget.folder, q: q);
      if (!mounted || q != _lastQuery) return; // the user typed more meanwhile
      setState(() {
        _results = page.messages;
        _total = page.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Message m) async {
    await Navigator.pushNamed(context, '/read', arguments: m.id);
    if (mounted) _search(); // refresh (read / trashed)
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _ctrl.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ① search box
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              height: 52,
              decoration: BoxDecoration(color: AppColors.bg2, borderRadius: BorderRadius.circular(26)),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close search',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onTyping,
                      onSubmitted: (_) => _search(),
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Search mail',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (hasQuery)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _ctrl.clear();
                        _onTyping('');
                      },
                    ),
                ],
              ),
            ),

            // ② folder chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(widget.folderName),
                    selected: !_allFolders,
                    onSelected: (_) {
                      setState(() => _allFolders = false);
                      _search();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('All folders'),
                    selected: _allFolders,
                    onSelected: (_) {
                      setState(() => _allFolders = true);
                      _search();
                    },
                  ),
                ],
              ),
            ),
            if (_loading) LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
            const Divider(),
            Expanded(child: _body(hasQuery)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool hasQuery) {
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: AppColors.error)));
    }
    if (!hasQuery) {
      return Center(
        child: Text('Search by sender, subject or text', style: TextStyle(color: AppColors.muted)),
      );
    }
    if (_results.isEmpty && !_loading) {
      // ④ empty state
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.border),
            SizedBox(height: 8),
            Text('No matches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }
    // ③ results
    return ListView.separated(
      itemCount: _results.length + 1,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text('$_total RESULT${_total == 1 ? '' : 'S'}',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
          );
        }
        final m = _results[i - 1];
        return MessageRow(
          message: m,
          showRecipient: m.folder == 'sent' || m.folder == 'drafts',
          onTap: () => _open(m),
        );
      },
    );
  }
}
