import 'package:flutter/material.dart';

/// The Twine mark. Same four strands as `branding/twine-logo.svg`.
class TwineLogo extends StatelessWidget {
  const TwineLogo({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved =
        color ??
        (theme.brightness == Brightness.dark
            ? theme.colorScheme.primary
            : const Color(0xFF3C245C));
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TwineLogoPainter(resolved)),
    );
  }
}

class TwineTitle extends StatelessWidget {
  const TwineTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TwineLogo(size: 22),
        const SizedBox(width: 10),
        Text(text),
      ],
    );
  }
}

class _TwineLogoPainter extends CustomPainter {
  const _TwineLogoPainter(this.color);

  final Color color;

  static const _outer = Radius.circular(55);
  static const _inner = Radius.circular(33);

  /// Square crop of the 245×225 trace, centered on the knot.
  static const _viewOrigin = Offset(10, 0);
  static const _viewSize = 225.0;

  static final List<Path> _strands = [
    _strand(
      const Offset(116, 151.5),
      const Offset(100.5, 167),
      const Offset(32, 98.5),
      const Offset(110, 20.5),
      const Offset(113.8, 26.1),
      const Offset(98.3, 41.6),
      const Offset(94.3, 36.2),
      const Offset(47.5, 83),
    ),
    _strand(
      const Offset(83.5, 106),
      const Offset(68, 90.5),
      const Offset(136.5, 22),
      const Offset(214.5, 100),
      const Offset(208.9, 103.8),
      const Offset(193.4, 88.3),
      const Offset(198.8, 84.3),
      const Offset(152, 37.5),
    ),
    _strand(
      const Offset(129, 73.5),
      const Offset(144.5, 58),
      const Offset(213, 126.5),
      const Offset(135, 204.5),
      const Offset(131.2, 198.9),
      const Offset(146.7, 183.4),
      const Offset(150.7, 188.8),
      const Offset(197.5, 142),
    ),
    _strand(
      const Offset(161.5, 119),
      const Offset(177, 134.5),
      const Offset(108.5, 203),
      const Offset(30.5, 125),
      const Offset(36.1, 121.2),
      const Offset(51.6, 136.7),
      const Offset(46.2, 140.7),
      const Offset(93, 187.5),
    ),
  ];

  static Path _strand(
    Offset start,
    Offset flat,
    Offset outerStart,
    Offset outerCorner,
    Offset outerTip,
    Offset innerTip,
    Offset innerCorner,
    Offset innerEnd,
  ) {
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(flat.dx, flat.dy)
      ..lineTo(outerStart.dx, outerStart.dy)
      ..arcToPoint(outerCorner, radius: _outer, clockwise: true)
      ..arcToPoint(outerTip, radius: _outer, clockwise: true)
      ..lineTo(innerTip.dx, innerTip.dy)
      ..arcToPoint(innerCorner, radius: _inner, clockwise: false)
      ..arcToPoint(innerEnd, radius: _inner, clockwise: false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _viewSize;
    canvas.translate(
      (size.width - _viewSize * scale) / 2 - _viewOrigin.dx * scale,
      (size.height - _viewSize * scale) / 2 - _viewOrigin.dy * scale,
    );
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final strand in _strands) {
      canvas.drawPath(strand, paint);
    }
  }

  @override
  bool shouldRepaint(_TwineLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
