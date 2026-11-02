import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rank on the Losertown ladder, earned by where your BMI sits.
///
/// Levels climb toward the healthy range (BMI 18.5–25), which is the top of
/// the ladder. Being under it isn't a higher level: it's [featherweight], a
/// side quest whose goal is to gain back into the healthy range.
///
/// The jokes are about the journey, never about bodies.
enum BmiRank {
  featherweight(
    level: 0,
    title: 'Featherweight',
    tagline: 'Light as a feather. Your side quest: refuel and build strength.',
    minBmi: 0,
    maxBmi: 18.5,
    icon: Icons.air,
    color: Color(0xFF3F8FC4),
  ),
  freshRecruit(
    level: 1,
    title: 'Fresh Recruit',
    tagline: 'Bags packed, boots laced. Every legend starts right here.',
    minBmi: 40,
    maxBmi: double.infinity,
    icon: Icons.backpack_outlined,
    color: Color(0xFF6B7C93),
  ),
  trailScout(
    level: 2,
    title: 'Trail Scout',
    tagline: 'You found the path. Keep the compass pointing down.',
    minBmi: 35,
    maxBmi: 40,
    icon: Icons.explore_outlined,
    color: Color(0xFF7A5BC7),
  ),
  apprenticeShredder(
    level: 3,
    title: 'Apprentice Shredder',
    tagline: 'Learning the ancient art of the calorie deficit.',
    minBmi: 30,
    maxBmi: 35,
    icon: Icons.local_fire_department_outlined,
    color: Color(0xFFD9622B),
  ),
  journeymanBurner(
    level: 4,
    title: 'Journeyman Burner',
    tagline: 'The forge is hot and the results are showing.',
    minBmi: 27.5,
    maxBmi: 30,
    icon: Icons.whatshot,
    color: Color(0xFFC7354A),
  ),
  eliteRanger(
    level: 5,
    title: 'Elite Ranger',
    tagline: 'Swift, steady, and closing in on the crown.',
    minBmi: 25,
    maxBmi: 27.5,
    icon: Icons.bolt,
    color: Color(0xFF1F8A5B),
  ),
  legend(
    level: 6,
    title: 'Legend of Losertown',
    tagline: 'Healthy range unlocked. The crown is yours, so keep it.',
    minBmi: 18.5,
    maxBmi: 25,
    icon: Icons.workspace_premium,
    color: Color(0xFFB8860B),
  );

  const BmiRank({
    required this.level,
    required this.title,
    required this.tagline,
    required this.minBmi,
    required this.maxBmi,
    required this.icon,
    required this.color,
  });

  /// 1 (Fresh Recruit) to [maxLevel] (Legend); 0 for the Featherweight side
  /// quest.
  final int level;
  final String title;
  final String tagline;

  /// This rank covers BMIs from [minBmi] (inclusive) up to [maxBmi].
  final double minBmi;
  final double maxBmi;
  final IconData icon;

  /// Mid-tone, readable under white text in light and dark themes.
  final Color color;

  static const int maxLevel = 6;

  /// The main ladder, lowest level first.
  static const List<BmiRank> ladder = [
    freshRecruit,
    trailScout,
    apprenticeShredder,
    journeymanBurner,
    eliteRanger,
    legend,
  ];

  static BmiRank forBmi(double bmi) {
    for (final rank in values) {
      if (bmi >= rank.minBmi && bmi < rank.maxBmi) return rank;
    }
    return freshRecruit;
  }

  bool get isSideQuest => this == featherweight;
  bool get isTop => this == legend;

  /// The rank to aim for next: one level up, or back to Legend from the
  /// side quest. Null at the top.
  BmiRank? get next => switch (this) {
    featherweight => legend,
    legend => null,
    _ => ladder[ladder.indexOf(this) + 1],
  };
}

/// Body-mass index for [weightKg] at [heightCm].
double bmiOf(double weightKg, double heightCm) {
  final m = heightCm / 100;
  return weightKg / (m * m);
}

/// The weight that gives [bmi] at [heightCm].
double weightForBmi(double bmi, double heightCm) {
  final m = heightCm / 100;
  return bmi * m * m;
}

/// Where someone stands on the ladder, and what it takes to rank up.
class RankStatus {
  RankStatus({required this.weightKg, required this.heightCm})
    : bmi = bmiOf(weightKg, heightCm) {
    rank = BmiRank.forBmi(bmi);
  }

  final double weightKg;
  final double heightCm;
  final double bmi;
  late final BmiRank rank;

  /// Weight to lose (positive) or gain (negative, Featherweight only) to
  /// reach [BmiRank.next]; null at the top.
  double? get kgToNext {
    final next = rank.next;
    if (next == null) return null;
    if (rank.isSideQuest) return weightKg - weightForBmi(next.minBmi, heightCm);
    return weightKg - weightForBmi(rank.minBmi, heightCm);
  }

  /// How far through this rank's band toward the next, 0–1. The open-ended
  /// first rank measures from BMI 45.
  double get progress {
    if (rank.isTop) return 1;
    if (rank.isSideQuest) {
      return (bmi / rank.maxBmi).clamp(0.0, 1.0);
    }
    final top = math.min(rank.maxBmi, 45.0);
    return ((top - bmi) / (top - rank.minBmi)).clamp(0.0, 1.0);
  }
}
