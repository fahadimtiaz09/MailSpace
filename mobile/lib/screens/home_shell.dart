// home_shell.dart — the logged-in part of the app.
// Bottom bar with 3 tabs (same on every logged-in screen, like the wireframe):
//   Mail      → A5 Inbox  (inbox_screen.dart)
//   Domains   → A10 My domains   (temporary page for now)
//   Settings  → A12 Settings     (temporary page for now — has Log out)

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import '../theme.dart';
import 'inbox_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // 0 Mail, 1 Domains, 2 Settings
  late final Future<User?> _user = ApiClient.instance.me();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _user,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.ink)));
        }
        final user = snapshot.data;
        if (user == null) {
          // Session expired (or temporary account ended) → back to Welcome.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
          });
          return const Scaffold();
        }

        return Scaffold(
          // IndexedStack keeps each tab alive, so the inbox doesn't reload
          // every time you switch tabs.
          body: IndexedStack(
            index: _tab,
            children: [
              InboxScreen(
                user: user,
                onOpenDomains: () => setState(() => _tab = 1),
                onOpenSettings: () => setState(() => _tab = 2),
              ),
              const _ComingSoonTab(title: 'My domains', icon: Icons.language),
              _TemporarySettings(user: user),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.selected,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.mail_outline), selectedIcon: Icon(Icons.mail), label: 'Mail'),
              NavigationDestination(icon: Icon(Icons.language), label: 'Domains'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  final String title;
  final IconData icon;
  const _ComingSoonTab({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.border),
            const SizedBox(height: 12),
            const Text('Coming in a later step', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// TEMPORARY Settings tab until A12 is built: shows the account and Log out.
class _TemporarySettings extends StatelessWidget {
  final User user;
  const _TemporarySettings({required this.user});

  Future<void> _logout(BuildContext context) async {
    try {
      await ApiClient.instance.logout();
    } catch (_) {
      // cookies are cleared on the phone anyway
    }
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.brandPanel,
                child: Text(user.initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(user.email, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    if (user.isTemporary)
                      Text('Temporary · ${user.daysLeft} days left',
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('The full Settings screen (A12) comes in a later step.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text('Log out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
