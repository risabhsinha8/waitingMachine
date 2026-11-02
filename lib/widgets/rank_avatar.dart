import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/bmi_rank.dart';

/// A friendly cartoon of the user: build follows [bmi], gear follows [rank].
/// With no [bmi] it's a grey mystery figure waiting for a weigh-in.
///
/// [bmi] animates, so the figure slims down (or fills out) smoothly as new
/// weigh-ins move the trend.
class RankAvatar extends StatelessWidget {
  const RankAvatar({
    super.key,
    required this.bmi,
    required this.sex,
    this.size = 120,
  });

  final double? bmi;
  final Sex sex;

  /// Width; height is 1.2× this.
  final double size;

  @override
  Widget build(BuildContext context) {
    final bmi = this.bmi;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      image: true,
      label: bmi == null
          ? 'Mystery avatar'
          : 'Avatar, ${BmiRank.forBmi(bmi).title}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: bmi ?? 24),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, animatedBmi, _) => CustomPaint(
          size: Size(size, size * 1.2),
          painter: _AvatarPainter(
            bmi: animatedBmi,
            // The gear changes at the real value, not mid-animation.
            rank: bmi == null ? null : BmiRank.forBmi(bmi),
            sex: sex,
            shadow: scheme.onSurface.withValues(alpha: dark ? 0.25 : 0.12),
          ),
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter({
    required this.bmi,
    required this.rank,
    required this.sex,
    required this.shadow,
  });

  final double bmi;

  /// Null draws the mystery figure.
  final BmiRank? rank;
  final Sex sex;
  final Color shadow;

  static const _skin = Color(0xFFF6C99A);
  static const _skinShade = Color(0xFFE3AE7C);
  static const _hair = Color(0xFF4A3426);
  static const _pants = Color(0xFF3B4252);
  static const _shoes = Color(0xFFF2F2F2);
  static const _ink = Color(0xFF2B2B2B);
  static const _gold = Color(0xFFF2C230);
  static const _mystery = Color(0xFF9AA3AD);

  // Drawn on a 100 × 120 grid, scaled to fit.
  static const double _cx = 50;

  /// Body width multiplier: slim at BMI 16, broad at 46.
  double get _build => 0.72 + 0.83 * ((bmi - 16) / 30).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 120);
    final rank = this.rank;
    final mystery = rank == null;
    final shirt = mystery ? _mystery : rank.color;
    final skin = mystery ? _mystery.withValues(alpha: 0.7) : _skin;
    final w = _build;
    final torsoW = 30 * w;
    final half = torsoW / 2;

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(_cx, 113),
        width: 26 + 20 * w,
        height: 6,
      ),
      Paint()..color = shadow,
    );

    // Cape, behind everything.
    if (rank == BmiRank.eliteRanger || rank == BmiRank.legend) {
      final cape = Path()
        ..moveTo(_cx - half + 2, 52)
        ..quadraticBezierTo(_cx - half - 14, 86, _cx - half - 10, 104)
        ..lineTo(_cx + half + 10, 104)
        ..quadraticBezierTo(_cx + half + 14, 86, _cx + half - 2, 52)
        ..close();
      canvas.drawPath(
        cape,
        Paint()
          ..color = rank == BmiRank.legend
              ? const Color(0xFFB3261E)
              : Color.lerp(shirt, Colors.black, 0.35)!,
      );
    }

    // Ponytail sits behind the head, swinging out to one side.
    if (sex == Sex.female && !mystery) {
      canvas.save();
      canvas.translate(_cx + 17, 30);
      canvas.rotate(0.35);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, 8), width: 11, height: 24),
        Paint()..color = _hair,
      );
      canvas.restore();
    }

    // Legs and shoes.
    final legW = 9 * (0.85 + 0.3 * w);
    final legGap = 2 + 4 * w;
    for (final side in [-1.0, 1.0]) {
      final x = _cx + side * (legGap / 2 + legW / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, 96), width: legW, height: 26),
          const Radius.circular(4),
        ),
        Paint()..color = mystery ? _mystery : _pants,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + side * 2, 109),
          width: legW + 5,
          height: 6,
        ),
        Paint()..color = mystery ? _mystery : _shoes,
      );
    }

    // Arms, drawn under the torso so the shoulders tuck in.
    _arms(canvas, rank, half, w, shirt, skin);

    // Torso.
    final torso = RRect.fromRectAndRadius(
      Rect.fromLTRB(_cx - half, 50, _cx + half, 88),
      Radius.circular(math.min(half, 10 + 6 * w)),
    );
    canvas.drawRRect(torso, Paint()..color = shirt);

    // Backpack straps for the Fresh Recruit.
    if (rank == BmiRank.freshRecruit) {
      final strap = Paint()
        ..color = Color.lerp(shirt, Colors.black, 0.4)!
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(_cx - half * 0.55, 51),
        Offset(_cx - half * 0.45, 80),
        strap,
      );
      canvas.drawLine(
        Offset(_cx + half * 0.55, 51),
        Offset(_cx + half * 0.45, 80),
        strap,
      );
    }

    // Chest emblem.
    if (mystery) {
      _glyph(canvas, '?', const Offset(_cx, 69), 16, Colors.white, bold: true);
    } else if (rank.level >= 3 || rank.isSideQuest) {
      _icon(canvas, rank.icon, const Offset(_cx, 68), 14, Colors.white);
    }

    // Neck and head.
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(_cx, 49), width: 8, height: 6),
      Paint()..color = mystery ? skin : _skinShade,
    );
    canvas.drawCircle(const Offset(_cx, 33), 15, Paint()..color = skin);

    if (mystery) return;

    _hairOn(canvas);
    _face(canvas, rank);
    _headgear(canvas, rank, shirt);
  }

  void _arms(
    Canvas canvas,
    BmiRank? rank,
    double half,
    double w,
    Color shirt,
    Color skin,
  ) {
    final sleeve = Paint()
      ..color = shirt
      ..strokeWidth = 7 * (0.85 + 0.25 * w)
      ..strokeCap = StrokeCap.round;
    final hand = Paint()..color = skin;
    final shoulderY = 56.0;

    void limb(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = sleeve.color
          ..strokeWidth = sleeve.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(points.last, sleeve.strokeWidth * 0.55, hand);
    }

    for (final side in [-1.0, 1.0]) {
      final shoulder = Offset(_cx + side * (half - 3), shoulderY);
      final points = switch (rank) {
        // Victory pose: both arms up.
        BmiRank.legend => [
          shoulder,
          Offset(_cx + side * (half + 9), 42),
          Offset(_cx + side * (half + 13), 28),
        ],
        // Flexing.
        BmiRank.eliteRanger || BmiRank.journeymanBurner => [
          shoulder,
          Offset(_cx + side * (half + 12), 60),
          Offset(_cx + side * (half + 13), 47),
        ],
        // A cheerful wave with one hand.
        BmiRank.freshRecruit when side > 0 => [
          shoulder,
          Offset(_cx + side * (half + 10), 48),
          Offset(_cx + side * (half + 15), 36),
        ],
        _ => [shoulder, Offset(_cx + side * (half + 6), 80)],
      };
      limb(points);
    }
  }

  void _hairOn(Canvas canvas) {
    final hair = Paint()..color = _hair;
    // A cap of hair over the top of the head, with a side-swept fringe.
    final path = Path()
      ..addArc(
        Rect.fromCircle(center: const Offset(_cx, 33), radius: 15.5),
        math.pi * 1.02,
        math.pi * 0.96,
      )
      ..quadraticBezierTo(_cx + 8, 22, _cx - 2, 26)
      ..quadraticBezierTo(_cx - 9, 28, _cx - 15.3, 31)
      ..close();
    canvas.drawPath(path, hair);
  }

  void _face(Canvas canvas, BmiRank rank) {
    final ink = Paint()..color = _ink;
    canvas.drawCircle(const Offset(_cx - 5.5, 34), 1.7, ink);
    canvas.drawCircle(const Offset(_cx + 5.5, 34), 1.7, ink);
    final blush = Paint()..color = const Color(0x55FF7B7B);
    canvas.drawCircle(const Offset(_cx - 9, 39), 2.6, blush);
    canvas.drawCircle(const Offset(_cx + 9, 39), 2.6, blush);
    // The grin widens as you climb.
    final grin = 4.5 + rank.level * 0.5;
    canvas.drawArc(
      Rect.fromCenter(
        center: const Offset(_cx, 38),
        width: grin * 2,
        height: 7,
      ),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  void _headgear(Canvas canvas, BmiRank rank, Color shirt) {
    switch (rank) {
      case BmiRank.freshRecruit:
        // A baseball cap with the brim to the side.
        final cap = Paint()..color = shirt;
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(_cx, 31), radius: 15.5),
          math.pi,
          math.pi,
          true,
          cap,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(_cx + 6, 28.5, 16, 4),
            const Radius.circular(2),
          ),
          Paint()..color = Color.lerp(shirt, Colors.black, 0.3)!,
        );
      case BmiRank.legend:
        _crown(canvas);
      case BmiRank.featherweight:
        // A feather tucked in the hair.
        final feather = Path()
          ..moveTo(_cx + 9, 22)
          ..quadraticBezierTo(_cx + 22, 6, _cx + 17, 0)
          ..quadraticBezierTo(_cx + 12, 10, _cx + 9, 22)
          ..close();
        canvas.drawPath(feather, Paint()..color = Colors.white);
        canvas.drawPath(
          feather,
          Paint()
            ..color = shirt
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      case BmiRank.trailScout ||
          BmiRank.apprenticeShredder ||
          BmiRank.journeymanBurner ||
          BmiRank.eliteRanger:
        // A sweatband, with trailing ties from Apprentice up.
        final band = Paint()..color = shirt;
        canvas.save();
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(center: const Offset(_cx, 33), radius: 15.6),
          ),
        );
        canvas.drawRect(const Rect.fromLTWH(_cx - 16, 23.5, 32, 4.5), band);
        canvas.restore();
        if (rank.level >= 3) {
          final tie = Paint()
            ..color = shirt
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            const Offset(_cx - 14.5, 26),
            const Offset(_cx - 23, 31),
            tie,
          );
          canvas.drawLine(
            const Offset(_cx - 14.5, 26),
            const Offset(_cx - 22, 23),
            tie,
          );
        }
    }
  }

  void _crown(Canvas canvas) {
    final crown = Path()
      ..moveTo(_cx - 12, 21)
      ..lineTo(_cx - 13, 9)
      ..lineTo(_cx - 6.5, 15)
      ..lineTo(_cx, 6)
      ..lineTo(_cx + 6.5, 15)
      ..lineTo(_cx + 13, 9)
      ..lineTo(_cx + 12, 21)
      ..close();
    canvas.drawPath(crown, Paint()..color = _gold);
    canvas.drawPath(
      crown,
      Paint()
        ..color = const Color(0xFFB8860B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
    final gem = Paint()..color = const Color(0xFFB3261E);
    canvas.drawCircle(const Offset(_cx, 16.5), 1.8, gem);
    canvas.drawCircle(const Offset(_cx - 7, 17.5), 1.3, gem);
    canvas.drawCircle(const Offset(_cx + 7, 17.5), 1.3, gem);
  }

  void _icon(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color color,
  ) => _paintText(
    canvas,
    TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: color,
      ),
    ),
    center,
  );

  void _glyph(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color, {
    bool bold = false,
  }) => _paintText(
    canvas,
    TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w800 : null,
      ),
    ),
    center,
  );

  void _paintText(Canvas canvas, TextSpan span, Offset center) {
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.bmi != bmi ||
      old.rank != rank ||
      old.sex != sex ||
      old.shadow != shadow;
}
