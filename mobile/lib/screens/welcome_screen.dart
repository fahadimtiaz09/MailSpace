// welcome_screen.dart — wireframe A1 · Welcome
// Looks like the website's sign-in pages: a deep-blue brand panel with the
// MailSpace logo on top, then the message and two buttons.
//   Create account → A2 Sign up   (route '/signup')
//   Log in         → A3 Log in    (route '/login')

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/theme_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand panel (same deep-blue gradient as the website)
                  Container(
                    padding: EdgeInsets.fromLTRB(28, MediaQuery.of(context).padding.top + 24, 28, 28),
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-0.6, -0.8),
                        radius: 1.4,
                        colors: [Color(0xFF16285A), Color(0xFF070D1C)],
                      ),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo on the left, 🌙 / ☀️ on the right (like the website header)
                        const Row(
                          children: [
                            BrandLockup(logoWidth: 48, fontSize: 26, onDark: true),
                            Spacer(),
                            ThemeButton(onDark: true),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Big logo in a soft glowing circle
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFF2F6BFF).withValues(alpha: .35),
                                  const Color(0xFF2F6BFF).withValues(alpha: 0),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const MailSpaceLogo(width: 88, onDark: true),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'PROFESSIONAL EMAIL HOSTING',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: Color(0xFF91B5FF),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Professional email, on your own domain.',
                          style: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                    child: Text(
                      'Your own @fahadimtiaz.site address in seconds. '
                      'Connect a domain whenever you\'re ready.',
                      style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.muted),
                    ),
                  ),
                  // Three feature cards (like the website's feature highlights)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      children: [
                        _feature(Icons.language, 'Your own domain',
                            'Create addresses on a domain you own, like info@yourbusiness.com.'),
                        _feature(Icons.inbox_outlined, 'A calmer inbox',
                            'Folders, search, stars and attachments — clean and simple.'),
                        _feature(Icons.lock_outline, 'Secure & private',
                            'Hashed passwords and plain-text reading. Free to start.'),
                      ],
                    ),
                  ),

                  const Spacer(), // pushes the buttons to the bottom
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: () => Navigator.pushNamed(context, '/signup'),
                          child: const Text('Create account'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => Navigator.pushNamed(context, '/login'),
                          child: const Text('Log in'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One feature card: blue icon box · title · one line of text.
  Widget _feature(IconData icon, String title, String text) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}
