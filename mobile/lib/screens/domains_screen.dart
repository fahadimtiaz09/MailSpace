// domains_screen.dart — wireframe A10 · My domains  (the "Domains" tab)
// Uses GET /api/domains  and  POST /api/domains
//
//   ① title + how many of the 3 allowed domains are used
//   ② verified domain card → tap → A11 manage addresses
//   ③ pending domain card  → tap → A11 finish verification
//   ④ info box about sending to Gmail / Outlook
//   ⑤ "Add domain" button (hidden at 3 domains) → type a name → A11

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/domain.dart';
import '../theme.dart';
import 'domain_detail_screen.dart';

class DomainsScreen extends StatefulWidget {
  const DomainsScreen({super.key});

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  static const maxDomains = 3;

  List<Domain>? _domains;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiClient.instance.getDomains();
      if (mounted) {
        setState(() {
          _domains = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openDomain(Domain d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => DomainDetailScreen(domain: d)));
    if (mounted) _load();
  }

  /// ⑤ Step 1 of the wizard: type the domain name.
  Future<void> _addDomain() async {
    final created = await showModalBottomSheet<Domain>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AddDomainSheet(),
    );
    if (created != null && mounted) {
      await _openDomain(created); // straight to step 2 (verify)
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _domains;
    final canAdd = list != null && list.length < maxDomains;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My domains', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          if (list != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${list.length} of $maxDomains',
                    style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
            ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: _addDomain,
              backgroundColor: AppColors.primaryBtn,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add domain', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _load();
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
            )
          : list == null
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
      color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    children: [
                      Text('Use your own domain with MailSpace. Each account can connect up to 3 domains.',
                          style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      const SizedBox(height: 14),
                      if (list.isEmpty) _emptyState(),
                      for (final d in list) _DomainCard(domain: d, onTap: () => _openDomain(d)),
                      const SizedBox(height: 4),
                      // ④ info box
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.primarySofter, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: AppColors.ink),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Mail sent to an address on your domain arrives in this inbox. '
                                'Mail to Gmail, Outlook and other providers is sent from your main MailSpace address.',
                                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _emptyState() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(Icons.language, size: 40, color: AppColors.muted),
            const SizedBox(height: 8),
            const Text('Add your first domain', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('We\'ll walk you through it step by step.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _addDomain,
              style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
              child: const Text('Add a domain'),
            ),
          ],
        ),
      );
}

/// ② / ③ one domain card
class _DomainCard extends StatelessWidget {
  final Domain domain;
  final VoidCallback onTap;
  const _DomainCard({required this.domain, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = domain;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: d.isVerified ? AppColors.border : AppColors.inputBorder, width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.language, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(d.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: d.isVerified ? AppColors.successSoft : AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(d.isVerified ? 'Verified' : 'Waiting for DNS',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: d.isVerified ? AppColors.success : AppColors.warning)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _kv('Ownership', d.isVerified ? 'Verified' : 'Not yet'),
              if (d.isVerified) _kv('Addresses', '${d.addresses.length} created'),
              if (d.isVerified) _kv('Email authentication', 'Not configured'),
              const SizedBox(height: 6),
              Text(d.isVerified ? 'Manage →' : 'Finish setup →',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(k, style: TextStyle(fontSize: 13, color: AppColors.muted))),
            Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Bottom sheet: "Step 1 · Your domain"
class _AddDomainSheet extends StatefulWidget {
  const _AddDomainSheet();

  @override
  State<_AddDomainSheet> createState() => _AddDomainSheetState();
}

class _AddDomainSheetState extends State<_AddDomainSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) {
      setState(() => _error = 'Type your domain, for example yourbusiness.com');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ApiClient.instance.addDomain(_ctrl.text);
      if (mounted) Navigator.pop(context, d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // move up above the keyboard
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 1 · Your domain', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Type the domain you own. Next, we\'ll show you one DNS record to add.',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(hintText: 'yourbusiness.com', errorText: _error, errorMaxLines: 3),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
