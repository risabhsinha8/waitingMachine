import 'package:flutter/material.dart';

/// Dash pattern per series slot: a second cue besides color for telling
/// predictions apart.
const List<List<int>> _dashes = [
  [8, 4],
  [3, 3],
  [12, 4, 3, 4],
  [6, 6],
  [2, 5],
  [10, 3],
  [5, 2, 1, 2],
  [14, 6],
];

List<int> seriesDash(int slot) => _dashes[slot % _dashes.length];

/// A short stroke that mirrors a series' line style, keying a name to its
/// line on the chart.
class SeriesKey extends StatelessWidget {
  const SeriesKey({
    super.key,
    required this.color,
    this.dash,
    this.width = 2,
    this.dot = false,
    this.length = 20,
  });

  final Color color;
  final List<int>? dash;
  final double width;
  final bool dot;
  final double length;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(length, 10),
    painter: _SeriesKeyPainter(
      color: color,
      dash: dash,
      width: width,
      dot: dot,
    ),
  );
}

class _SeriesKeyPainter extends CustomPainter {
  _SeriesKeyPainter({
    required this.color,
    required this.dash,
    required this.width,
    required this.dot,
  });

  final Color color;
  final List<int>? dash;
  final double width;
  final bool dot;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final pattern = dash;
    if (pattern == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      var x = 0.0;
      for (var i = 0; x < size.width; i++) {
        final length = pattern[i % pattern.length].toDouble();
        if (i.isEven) {
          canvas.drawLine(
            Offset(x, y),
            Offset((x + length).clamp(0, size.width), y),
            paint,
          );
        }
        x += length;
      }
    }
    if (dot) canvas.drawCircle(Offset(size.width / 2, y), 3.5, paint);
  }

  @override
  bool shouldRepaint(_SeriesKeyPainter old) =>
      old.color != color || old.dash != dash || old.width != width;
}
