import 'package:flutter/material.dart';

/// The Twine mark. Same four strands as `twine-logo.svg`.
class TwineLogo extends StatelessWidget {
  const TwineLogo({
    super.key,
    this.size = 24,
    this.color = const Color(0xFF3C245C),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TwineLogoPainter(color)),
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

  static const _strands = <List<double>>[
    [2.52, 15.54, 4.79, 13.27, 9.88, 20.06, 12.14, 17.8],
    [5.64, 12.42, 7.9, 10.16, 12.99, 16.95, 15.25, 14.69],
    [8.75, 9.31, 11.01, 7.05, 16.1, 13.84, 18.36, 11.58],
    [11.86, 6.2, 14.12, 3.94, 19.21, 10.73, 21.48, 8.46],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final strand in _strands) {
      final path = Path()
        ..moveTo(strand[0], strand[1])
        ..cubicTo(
          strand[2],
          strand[3],
          strand[4],
          strand[5],
          strand[6],
          strand[7],
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TwineLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
