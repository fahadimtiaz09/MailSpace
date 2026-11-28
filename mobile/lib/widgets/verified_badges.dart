// verified_badges.dart — Settings → Security: "Rated A+ for security by …".
// One quiet line, like the website footer. Each scanner name opens its live report.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

class VerifiedBadges extends StatefulWidget {
  const VerifiedBadges({super.key});

  @override
  State<VerifiedBadges> createState() => _VerifiedBadgesState();
}

class _VerifiedBadgesState extends State<VerifiedBadges> {
  static const _green = Color(0xFF2E9D57);
  final _taps = <TapGestureRecognizer>[];

  TextSpan _link(String name, String url) {
    final tap = TapGestureRecognizer()
      ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    _taps.add(tap);
    return TextSpan(
      text: name,
      recognizer: tap,
      style: const TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
    );
  }

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final base = TextStyle(fontSize: 13, height: 1.5, color: Theme.of(context).colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _green.withValues(alpha: .12)),
            child: const Icon(Icons.verified_user_outlined, color: _green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(style: base, children: [
                const TextSpan(text: 'Rated '),
                const TextSpan(text: 'A+', style: TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: ' for security by '),
                _link('Qualys SSL Labs', 'https://www.ssllabs.com/ssltest/analyze.html?d=domailit.com'),
                const TextSpan(text: ', '),
                _link('Mozilla Observatory', 'https://developer.mozilla.org/en-US/observatory/analyze?host=domailit.com'),
                const TextSpan(text: ' and '),
                _link('Security Headers', 'https://securityheaders.com/?q=domailit.com&followRedirects=on'),
                const TextSpan(text: '.\n'),
                TextSpan(
                  text: 'Independent public tests, open to anyone.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
