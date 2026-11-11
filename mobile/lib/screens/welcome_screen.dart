// welcome_screen.dart — wireframe A1 · Welcome
// First screen after install. Two buttons:
//   Create account → A2 Sign up   (route '/signup')
//   Log in         → A3 Log in    (route '/login')

import 'package:flutter/material.dart';

import '../theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // LayoutBuilder + scroll: buttons stay at the bottom on tall phones,
        // and the page scrolls instead of breaking on small phones.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 68),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App icon (dark rounded square with "M")
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'M',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // "MailSpace" — Mail bold, Space normal (like the website logo)
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Mail', style: TextStyle(fontWeight: FontWeight.w800)),
                          TextSpan(text: 'Space', style: TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      style: TextStyle(fontSize: 26, color: AppColors.ink),
                    ),
                    const SizedBox(height: 16),

                    // Illustration box (simple envelope for now)
                    Container(
                      height: 230,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.soft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border, width: 1.5),
                      ),
                      child: const Icon(Icons.mail_outline_rounded, size: 96, color: AppColors.muted),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      'Professional email, on your own domain.',
                      style: TextStyle(fontSize: 26, height: 1.25, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your own @fahadimtiaz.site address in seconds. '
                      'Connect a domain whenever you\'re ready.',
                      style: TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF4A4A46)),
                    ),

                    const Spacer(), // pushes the buttons to the bottom
                    const SizedBox(height: 24),

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
            ),
          ),
        ),
      ),
    );
  }
}
