// home_shell.dart — the logged-in part of the app.
// Bottom bar with 3 tabs (same on every logged-in screen, like the wireframe):
//   Mail      → A5 Inbox        (inbox_screen.dart)
//   Domains   → A10 My domains  (domains_screen.dart)
//   Settings  → A12 Settings    (settings_screen.dart)

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import '../services/call_service.dart';
import '../theme.dart';
import 'domains_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // 0 Mail, 1 Domains, 2 Settings
  late final Future<User?> _user = ApiClient.instance.me();

  @override
  void dispose() {
    CallService.instance.stop(); // logged out → not "online" any more
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _user,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
        }
        final user = snapshot.data;
        if (user == null) {
          // Session expired (or temporary account ended) → back to Welcome.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
          });
          return const Scaffold();
        }

        // Tell the server we're online (dial buttons turn blue for others)
        // and listen for incoming calls.
        CallService.instance.start(user.email);

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
              const DomainsScreen(),
              SettingsScreen(user: user, onOpenDomains: () => setState(() => _tab = 1)),
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
