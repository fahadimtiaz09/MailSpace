// domain_detail_screen.dart — wireframe A11 · Add / manage domain
// Steps: Domain ✓ → Verify → Addresses
//
//   Pending domain:
//     ② TXT record with Copy buttons
//     ③ step-by-step help per DNS provider
//     ④ status box + "Check now"   → POST /api/domains/<id>/verify
//   Verified domain:
//     ⑤ create addresses (up to 10) → POST   /api/domains/<id>/addresses
//        delete an address          → DELETE /api/domains/<id>/addresses/<aid>
//   Danger zone: Remove domain      → DELETE /api/domains/<id>

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models/domain.dart';
import '../theme.dart';

class DomainDetailScreen extends StatefulWidget {
  final Domain domain;
  const DomainDetailScreen({super.key, required this.domain});

  @override
  State<DomainDetailScreen> createState() => _DomainDetailScreenState();
}

class _DomainDetailScreenState extends State<DomainDetailScreen> {
  final _api = ApiClient.instance;
  final _addressCtrl = TextEditingController();

  late Domain _domain = widget.domain;
  bool _checking = false;
  bool _adding = false;
  String? _verifyMessage; // result of the last "Check now"
  bool _verifyFailed = false;
  String? _addressError;
  String _provider = 'Namecheap';

  static const _providerSteps = {
    'Namecheap': [
      'Open Domain List and click Manage next to your domain.',
      'Go to Advanced DNS and click Add New Record.',
      'Choose TXT Record. In Host type _mailspace and paste the value.',
      'Click the green check mark to save.',
    ],
    'Cloudflare': [
      'Open your domain and go to DNS → Records.',
      'Click Add record and choose type TXT.',
      'In Name type _mailspace and paste the value in Content.',
      'Click Save.',
    ],
    'Netlify DNS': [
      'Open Domains and choose your domain.',
      'In DNS settings click Add new record.',
      'Choose TXT, type _mailspace as Name and paste the value.',
      'Click Save.',
    ],
    'Other': [
      'Open the DNS settings of your domain provider.',
      'Add a new TXT record.',
      'Host / Name: _mailspace (some providers want _mailspace.yourdomain).',
      'Value: paste the value, then save.',
    ],
  };

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final all = await _api.getDomains();
      final fresh = all.where((d) => d.id == _domain.id);
      if (fresh.isNotEmpty && mounted) setState(() => _domain = fresh.first);
    } on ApiException {
      // keep what we have
    }
  }

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _verifyMessage = null;
    });
    try {
      final d = await _api.verifyDomain(_domain.id);
      if (!mounted) return;
      setState(() {
        _domain = d;
        _verifyFailed = !d.isVerified;
        _verifyMessage = d.isVerified ? '${d.name} is verified!' : 'Still waiting for DNS.';
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _verifyFailed = true;
          _verifyMessage = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _addAddress() async {
    final local = _addressCtrl.text.trim().toLowerCase();
    if (local.isEmpty) {
      setState(() => _addressError = 'Type the part before @, for example info');
      return;
    }
    setState(() {
      _adding = true;
      _addressError = null;
    });
    try {
      await _api.addAddress(_domain.id, local);
      _addressCtrl.clear();
      await _reload();
      _snack('$local@${_domain.name} created');
    } on ApiException catch (e) {
      if (mounted) setState(() => _addressError = e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteAddress(DomainAddress a) async {
    final yes = await _confirm('Delete ${a.email}?', 'Mail sent to this address will no longer arrive.', 'Delete');
    if (!yes) return;
    try {
      await _api.deleteAddress(_domain.id, a.id);
      await _reload();
      _snack('${a.email} deleted');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _removeDomain() async {
    final yes = await _confirm(
        'Remove ${_domain.name}?', 'This removes the domain and all its addresses. You can add it again later.', 'Remove');
    if (!yes) return;
    try {
      await _api.removeDomain(_domain.id);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action, style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return yes == true;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('$what copied');
  }

  @override
  Widget build(BuildContext context) {
    final d = _domain;
    return Scaffold(
      appBar: AppBar(title: Text(d.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            // ① step bar
            _StepBar(verified: d.isVerified),
            const SizedBox(height: 18),
            if (!d.isVerified) ..._verifySection(d) else ..._addressesSection(d),
            const SizedBox(height: 28),

            // Danger zone
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.error, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Remove domain', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('Removes the domain and its addresses.',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _removeDomain,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error, width: 1.5),
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- step 2: verify ----------------

  List<Widget> _verifySection(Domain d) {
    final record = d.dnsRecords.isNotEmpty ? d.dnsRecords.first : null;
    return [
      Text('Add this TXT record at your DNS provider, then tap Check now.',
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink)),
      const SizedBox(height: 12),

      // ② the record
      if (record != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _recordRow('Type', record.type, null),
              const Divider(),
              _recordRow('Host', record.host, () => _copy(record.host, 'Host')),
              const Divider(),
              _recordRow('Value', record.value, () => _copy(record.value, 'Value')),
            ],
          ),
        ),
      const SizedBox(height: 12),

      // ③ provider help
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text('Step-by-step for $_provider', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Namecheap · Cloudflare · Netlify DNS · Other', style: TextStyle(fontSize: 12)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _providerSteps.keys)
                    ChoiceChip(
                      label: Text(p),
                      selected: p == _provider,
                      onSelected: (_) => setState(() => _provider = p),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (i, step) in _providerSteps[_provider]!.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${i + 1}. $step', style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // ④ status
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _verifyFailed ? AppColors.errorSoft : AppColors.primarySofter,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_verifyFailed ? Icons.error_outline : Icons.hourglass_empty,
                color: _verifyFailed ? AppColors.error : AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _verifyMessage ?? 'Waiting for the DNS record. Changes can take a few minutes.',
                style: TextStyle(fontSize: 13, height: 1.4, color: _verifyFailed ? AppColors.error : AppColors.primary),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _checking ? null : _verify,
        child: _checking
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Text('Check now'),
      ),
      Center(
        child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('I\'ll do this later')),
      ),
    ];
  }

  Widget _recordRow(String label, String value, VoidCallback? onCopy) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 52, child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted))),
            Expanded(
              child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
            if (onCopy != null)
              TextButton(
                onPressed: onCopy,
                style: TextButton.styleFrom(minimumSize: const Size(56, 40)),
                child: const Text('Copy'),
              ),
          ],
        ),
      );

  // ---------------- step 3: addresses ----------------

  List<Widget> _addressesSection(Domain d) {
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.primarySofter, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, color: AppColors.success),
            SizedBox(width: 10),
            Expanded(child: Text('Domain verified — you can create email addresses on it.')),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text('New address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _addressCtrl,
              autocorrect: false,
              onSubmitted: (_) => _adding ? null : _addAddress(),
              decoration: InputDecoration(
                hintText: 'info',
                suffixText: '@${d.name}',
                errorText: _addressError,
                errorMaxLines: 3,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text('Lowercase letters, numbers, dot or underscore. Up to 10 addresses per domain.',
          style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: _adding || d.addresses.length >= 10 ? null : _addAddress,
        child: _adding
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Text('Create address'),
      ),
      const SizedBox(height: 20),
      Text('ADDRESSES (${d.addresses.length})',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
      const SizedBox(height: 6),
      if (d.addresses.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No addresses yet.', style: TextStyle(color: AppColors.muted)),
        ),
      for (final a in d.addresses)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: Text(a.email, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Delete ${a.email}',
                icon: Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _deleteAddress(a),
              ),
            ],
          ),
        ),
    ];
  }
}

/// ① Domain ✓ → Verify → Addresses
class _StepBar extends StatelessWidget {
  final bool verified;
  const _StepBar({required this.verified});

  @override
  Widget build(BuildContext context) {
    Widget dot(String text, {required bool done, required bool current}) => Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? AppColors.primary : Colors.transparent,
            border: Border.all(color: done || current ? AppColors.primary : AppColors.inputBorder, width: current ? 2 : 1.5),
          ),
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        );
    Widget line(bool on) =>
        Expanded(child: Container(height: 1.5, margin: const EdgeInsets.symmetric(horizontal: 6), color: on ? AppColors.primary : AppColors.border));

    return Row(
      children: [
        dot('1', done: true, current: false),
        const SizedBox(width: 6),
        const Text('Domain', style: TextStyle(fontSize: 12)),
        line(true),
        dot('2', done: verified, current: !verified),
        const SizedBox(width: 6),
        Text('Verify', style: TextStyle(fontSize: 12, fontWeight: verified ? FontWeight.w400 : FontWeight.w700)),
        line(verified),
        dot('3', done: false, current: verified),
        const SizedBox(width: 6),
        Text('Addresses',
            style: TextStyle(
                fontSize: 12,
                fontWeight: verified ? FontWeight.w700 : FontWeight.w400,
                color: verified ? AppColors.primary : AppColors.muted)),
      ],
    );
  }
}
