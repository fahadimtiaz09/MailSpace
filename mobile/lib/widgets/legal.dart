// legal.dart — Terms of Service / Privacy Policy
//
//   showTermsDialog(context)  → the "Privacy and Terms" step shown before a new
//                               account is created (true = "I agree").
//   openLegalPage(context, 'terms.html' | 'privacy.html') → opens the page in the browser.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

const _site = 'https://domailit.com';

Future<void> openLegalPage(BuildContext context, String page) async {
  final ok = await launchUrl(Uri.parse('$_site/$page'), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open $_site/$page in your browser.')));
  }
}

const _points = [
  (
    'Data we process when you use DoMailit',
    'Your username and password (stored only as a secure hash), the emails and attachments you send and receive, '
        'your call history (not the calls themselves), and technical data such as your IP address.'
  ),
  (
    'Why we process it',
    'To deliver your mail and calls, send the notifications you turn on, keep your account secure, and stop spam and abuse. '
        'We don\'t show ads and we never sell your data.'
  ),
  (
    'Keeping DoMailit safe',
    'Administrators may review messages and attachments for illegal or harmful content. Every review is recorded in an audit log.'
  ),
  (
    'Acceptable use',
    'No spam, scams, phishing, malware, harassment or illegal content. Accounts that break these rules can be suspended.'
  ),
  (
    'You\'re in control',
    'Hide your online status, turn notifications on or off, and delete your account and its data at any time from Settings.'
  ),
];

/// Full-screen "Privacy and Terms" page, like Gmail's. Returns true only for "I agree".
Future<bool> showTermsDialog(BuildContext context) async {
  final agreed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _TermsPage()),
  );
  return agreed == true;
}

class _TermsPage extends StatelessWidget {
  const _TermsPage();

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy and Terms', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  Icon(Icons.verified_user_outlined, size: 40, color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(
                    'To create a DoMailit account, you need to agree to the Terms of Service. '
                    'When you create an account, we process your information as described in our '
                    'Privacy Policy, including these key points:',
                    style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  for (final (title, text) in _points) ...[
                    const SizedBox(height: 14),
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(text, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted)),
                  ],
                  const SizedBox(height: 22),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Read the full '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: linkStyle,
                        recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(context, 'terms.html'),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: linkStyle,
                        recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(context, 'privacy.html'),
                      ),
                      const TextSpan(text: '.'),
                    ]),
                    style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('I agree'),
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
}
