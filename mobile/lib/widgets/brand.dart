// brand.dart — the MailSpace logo, the "MailSpace" name and coloured avatars,
// drawn the same way as on the website (frontend/home.html, style.css).

import 'package:flutter/material.dart';

import '../theme.dart';

/// The website logo: envelope + blue swoosh + paper plane.
/// Drawn in code (no image file needed). [onDark] = light colours for dark backgrounds.
class MailSpaceLogo extends StatelessWidget {
  final double width;
  final bool? onDark;
  const MailSpaceLogo({super.key, this.width = 42, this.onDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 40 / 48,
      child: CustomPaint(painter: _LogoPainter(onDark ?? AppColors.dark)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool onDark;
  _LogoPainter(this.onDark);

  @override
  void paint(Canvas canvas, Size size) {
    // The SVG is 48 × 40 — scale it to the widget size.
    canvas.scale(size.width / 48, size.height / 40);

    // Envelope
    final env = RRect.fromRectAndRadius(const Rect.fromLTWH(10.5, 7.5, 25, 19), const Radius.circular(4.2));
    canvas.drawRRect(
      env,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFD5DEFF)],
        ).createShader(env.outerRect),
    );
    if (!onDark) {
      canvas.drawRRect(
        env,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..color = const Color(0xFFC3D0F4),
      );
    }

    // Bottom fold lines
    canvas.drawPath(
      Path()
        ..moveTo(13, 26)
        ..lineTo(21, 19)
        ..moveTo(33, 26)
        ..lineTo(25, 19),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFC6D2F6),
    );

    // Blue "V" flap
    canvas.drawPath(
      Path()
        ..moveTo(12.6, 10.3)
        ..lineTo(23, 17.6)
        ..lineTo(33.4, 10.3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF2459D6),
    );

    // Swoosh
    final swoosh = Path()
      ..moveTo(41.5, 17.2)
      ..cubicTo(35, 24.6, 22.6, 30.8, 12.4, 31.4)
      ..cubicTo(5.6, 31.8, 4.2, 28.2, 8.6, 24.6)
      ..cubicTo(7, 28, 9.3, 29.6, 13.2, 29.4)
      ..cubicTo(22.5, 28.9, 33.5, 23.8, 41.5, 17.2)
      ..close();
    canvas.drawPath(
      swoosh,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Color(0xFF1FB6FF), Color(0xFF2F6BFF), Color(0xFF2459D6)],
          stops: [0, .55, 1],
        ).createShader(swoosh.getBounds()),
    );

    // Paper plane
    final plane = Path()
      ..moveTo(47, 2.2)
      ..lineTo(35.6, 7.3)
      ..lineTo(40, 9.1)
      ..lineTo(42, 13.8)
      ..close();
    canvas.drawPath(
      plane,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onDark
              ? const [Color(0xFFFFFFFF), Color(0xFFDCE4FF)]
              : const [Color(0xFF8FA8FF), Color(0xFF5B7CFF)],
        ).createShader(plane.getBounds()),
    );
    final fold = Path()
      ..moveTo(47, 2.2)
      ..lineTo(40, 9.1)
      ..lineTo(41.1, 11.4)
      ..close();
    canvas.drawPath(
      fold,
      Paint()..color = (onDark ? const Color(0xFF9DB2FF) : const Color(0xFF3E5FE0)).withValues(alpha: .55),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.onDark != onDark;
}

/// "Mail" in bold text colour + "Space" in the blue-to-purple gradient.
class BrandName extends StatelessWidget {
  final double fontSize;
  final bool onDark;
  const BrandName({super.key, this.fontSize = 22, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -.3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Mail', style: style.copyWith(color: onDark ? Colors.white : AppColors.ink)),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: onDark
                ? const [Color(0xFFCFE8FF), Color(0xFFE6DCFF)]
                : const [Color(0xFF1E9BFF), Color(0xFF4F7BFF), Color(0xFF8B5CF6)],
          ).createShader(rect),
          child: Text('Space', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

/// Logo + name together (top of Welcome, drawer, ...).
class BrandLockup extends StatelessWidget {
  final double logoWidth;
  final double fontSize;
  final bool onDark;
  const BrandLockup({super.key, this.logoWidth = 42, this.fontSize = 22, this.onDark = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MailSpaceLogo(width: logoWidth, onDark: onDark),
          const SizedBox(width: 8),
          BrandName(fontSize: fontSize, onDark: onDark),
        ],
      );
}

/// Round avatar with initials. Every address gets its own soft colour,
/// exactly like the website.
class Avatar extends StatelessWidget {
  final String seed;   // email address (decides the colour)
  final String text;   // initials
  final double radius;
  const Avatar({super.key, required this.seed, required this.text, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = AppColors.avatar(seed);
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(text, style: TextStyle(color: fg, fontSize: radius * .62, fontWeight: FontWeight.w700)),
    );
  }
}
