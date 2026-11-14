// brand.dart — the DoMailit logo, the "DoMailit" name and coloured avatars,
// drawn the same way as on the website (frontend/home.html, style.css).

import 'package:flutter/material.dart';

import '../services/people.dart';
import '../theme.dart';

/// The DoMailit logo: a blue "D" with a white envelope fold, and a navy "D"
/// behind it like a stack of mail. Drawn in code (no image file needed).
/// [onDark] = lighter back "D" for dark backgrounds.
class DoMailitLogo extends StatelessWidget {
  final double width;
  final bool? onDark;
  const DoMailitLogo({super.key, this.width = 32, this.onDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 46 / 42,
      child: CustomPaint(painter: _LogoPainter(onDark ?? AppColors.dark)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool onDark;
  _LogoPainter(this.onDark);

  static const blue = Color(0xFF2563EB);
  static const navy = Color(0xFF0B1F3A);

  /// A "D": flat on the left, round on the right (same as the SVG on the website).
  static Path _d(double dx, double dy) => Path()
    ..moveTo(3 + dx, 3 + dy)
    ..lineTo(18 + dx, 3 + dy)
    ..arcToPoint(Offset(18 + dx, 41 + dy), radius: const Radius.elliptical(17, 19))
    ..lineTo(3 + dx, 41 + dy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    // The SVG is 42 × 46 — scale it to the widget size.
    canvas.scale(size.width / 42, size.height / 46);
    canvas.drawPath(_d(4.5, 4), Paint()..color = onDark ? const Color(0xFFBFD3FF) : navy);
    canvas.drawPath(_d(0, 0), Paint()..color = blue);
    canvas.drawPath(
      Path()
        ..moveTo(3.6, 10.4)
        ..lineTo(17.6, 21.6)
        ..lineTo(32.2, 12.7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.7
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.onDark != onDark;
}

/// "Do" in blue + "Mailit" in navy (light blue + white on dark backgrounds).
class BrandName extends StatelessWidget {
  final double fontSize;
  final bool onDark;
  const BrandName({super.key, this.fontSize = 22, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -.3);
    final dark = onDark || AppColors.dark;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Do', style: style.copyWith(color: dark ? const Color(0xFF7CB1FF) : const Color(0xFF2563EB))),
        TextSpan(text: 'Mailit', style: style.copyWith(color: dark ? Colors.white : const Color(0xFF0B1F3A))),
      ]),
    );
  }
}

/// Logo + name together (top of Welcome, drawer, ...).
class BrandLockup extends StatelessWidget {
  final double logoWidth;
  final double fontSize;
  final bool onDark;
  const BrandLockup({super.key, this.logoWidth = 30, this.fontSize = 22, this.onDark = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DoMailitLogo(width: logoWidth, onDark: onDark ? true : null), // null = follow the app theme
          const SizedBox(width: 8),
          BrandName(fontSize: fontSize, onDark: onDark),
        ],
      );
}

/// Round avatar: the person's profile picture if they are a DoMailit user
/// with one, otherwise coloured initials (every address its own colour,
/// exactly like the website). [seed] is the email address.
class Avatar extends StatefulWidget {
  final String seed;   // email address (decides the colour, finds the picture)
  final String text;   // initials
  final double radius;
  const Avatar({super.key, required this.seed, required this.text, this.radius = 20});

  @override
  State<Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<Avatar> {
  @override
  void initState() {
    super.initState();
    People.instance.addListener(_changed);
    People.instance.want(widget.seed);
  }

  @override
  void didUpdateWidget(Avatar old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed) People.instance.want(widget.seed);
  }

  @override
  void dispose() {
    People.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final photo = People.instance.photoOf(widget.seed);
    if (photo != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.surface2,
        backgroundImage: MemoryImage(photo),
      );
    }
    final (bg, fg) = AppColors.avatar(widget.seed);
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      child: Text(widget.text,
          style: TextStyle(color: fg, fontSize: widget.radius * .62, fontWeight: FontWeight.w700)),
    );
  }
}
