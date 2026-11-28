// verified_seal.dart — the blue "verified" tick shown next to Premium users' names
// and DoMailit's own team/addresses. Same shape as the website (frontend/ui.js).
import 'dart:math' as math;

import 'package:flutter/material.dart';

class VerifiedSeal extends StatelessWidget {
  final String? kind; // 'premium', 'team' or null (nothing shown)
  final double size;
  const VerifiedSeal(this.kind, {super.key, this.size = 16});

  static const blue = Color(0xFF1D9BF0);

  @override
  Widget build(BuildContext context) {
    if (kind != 'premium' && kind != 'team') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: kind == 'team' ? 'Verified · Official DoMailit' : 'Verified · DoMailit Premium',
        child: CustomPaint(
          size: Size.square(size),
          painter: _SealPainter(blue),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  final Color color;
  _SealPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    // 12-scallop seal: 24 points alternating between two radii
    final seal = Path();
    for (var i = 0; i < 24; i++) {
      final r = (i.isEven ? 10.6 : 8.9) * s;
      final a = -math.pi / 2 + i * math.pi / 12;
      final p = Offset(12 * s + r * math.cos(a), 12 * s + r * math.sin(a));
      i == 0 ? seal.moveTo(p.dx, p.dy) : seal.lineTo(p.dx, p.dy);
    }
    seal.close();
    canvas.drawPath(seal, Paint()..color = color..isAntiAlias = true);
    final tick = Path()
      ..moveTo(7.6 * s, 12.3 * s)
      ..lineTo(10.6 * s, 15.3 * s)
      ..lineTo(16.4 * s, 9.1 * s);
    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SealPainter old) => old.color != color;
}
