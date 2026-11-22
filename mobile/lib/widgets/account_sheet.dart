// account_sheet.dart — Gmail-style account switcher.
//
// Tap your picture (Inbox top bar or the menu) → this sheet:
//   • the account in use, with "Manage your account" (Settings)
//   • every other account signed in on this phone — tap to switch
//   • "Add another account" → Log in (the others stay signed in)
//
// The server remembers which accounts are signed in (POST /api/auth/login with
// add=true, GET /api/auth/accounts, POST /api/auth/switch).

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import '../services/push_service.dart';
import '../theme.dart';
import 'brand.dart';

const maxAccounts = 5;

Future<void> showAccountSheet(BuildContext context, User user, {required VoidCallback onManage}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.elevated,
    builder: (_) => _AccountSheet(user: user, onManage: onManage),
  );
}

/// Opens another signed-in account: the whole app restarts as that account.
Future<void> switchToAccount(BuildContext context, String id) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await PushService.instance.beforeSwitch();
    await ApiClient.instance.switchAccount(id);
    navigator.pushNamedAndRemoveUntil('/home', (route) => false);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _AccountSheet extends StatefulWidget {
  final User user;
  final VoidCallback onManage;
  const _AccountSheet({required this.user, required this.onManage});

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  List<SignedInAccount>? _accounts;
  String? _switching;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.accounts().then((list) {
      if (mounted) setState(() => _accounts = list);
    }).catchError((_) {
      if (mounted) setState(() => _accounts = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final others = (_accounts ?? []).where((a) => !a.active).toList();
    final canAdd = _accounts != null && _accounts!.length < maxAccounts;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ① the account in use
            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Avatar(seed: u.email, text: u.initials, radius: 32),
                  const SizedBox(height: 10),
                  Text(u.displayName ?? u.username,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(u.email, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onManage();
                    },
                    child: const Text('Manage your account'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ② other accounts on this phone + "Add another account"
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (_accounts == null)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
                    ),
                  for (final a in others)
                    ListTile(
                      leading: Avatar(seed: a.email, text: a.initials, radius: 18),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(a.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: _switching == a.id
                          ? SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                          : null,
                      onTap: _switching != null
                          ? null
                          : () {
                              setState(() => _switching = a.id);
                              switchToAccount(context, a.id);
                            },
                    ),
                  if (others.isNotEmpty) Divider(height: 1, color: AppColors.border),
                  if (_accounts != null)
                    ListTile(
                      enabled: canAdd,
                      leading: Icon(Icons.person_add_alt_1_outlined, color: AppColors.primary),
                      title: const Text('Add another account'),
                      subtitle: canAdd ? null : Text('Up to $maxAccounts accounts on one phone'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/login', arguments: {'add': true});
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
