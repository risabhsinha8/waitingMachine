import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/app_models.dart';
import 'losertown_math.dart';

/// A realistic 30-day history for demos: three predictions locked in a month
/// ago at 85 kg, and daily weigh-ins that follow "Sustainable 1850 kcal".
class DemoData {
  const DemoData._({
    required this.profile,
    required this.predictions,
    required this.weightLogs,
    required this.checkpoints,
  });

  static const double startWeightKg = 85;
  static const int days = 30;
  static const String followedName = 'Sustainable 1850 kcal';

  /// Daily water-weight swing around the followed trajectory.
  static const double maxNoiseKg = 0.6;

  /// Chosen so the followed plan lands at ~82.8 kg after 30 days.
  static const _profile = UserProfile(heightCm: 175, age: 38, sex: Sex.male);
  static const _activity = ActivityLevel.lightlyActive;
  static const _plans = [
    ('Aggressive Cut (1500 kcal)', 1500.0),
    (followedName, 1850.0),
    ('Lazy 2150 kcal', 2150.0),
  ];

  final UserProfile profile;
  final List<PredictionSnapshot> predictions;
  final List<WeightLog> weightLogs;
  final List<Checkpoint> checkpoints;

  /// Deterministic for a given [seed], so demos and tests are repeatable.
  /// Keeps the caller's display [unit].
  static DemoData build({
    required DateTime now,
    WeightUnit unit = WeightUnit.kg,
    Uuid uuid = const Uuid(),
    int seed = 42,
  }) {
    final profile = _profile.copyWith(preferredUnit: unit);
    final created = DateTime(now.year, now.month, now.day - days, 8);
    final predictions = [
      for (final (name, kcal) in _plans)
        PredictionSnapshot(
          id: uuid.v4(),
          name: name,
          createdAt: created,
          startWeightKg: startWeightKg,
          dailyCalories: kcal,
          activityLevel: _activity,
          points: LosertownMath.generateProjection(
            profile: profile,
            startWeightKg: startWeightKg,
            dailyCalories: kcal,
            activityLevel: _activity,
            startDate: created,
          ),
        ),
    ];
    final followed = predictions.firstWhere((p) => p.name == followedName);

    // Water weight is sticky day to day, so the noise is autocorrelated
    // rather than independent, then clamped (leaving room for rounding).
    final random = math.Random(seed);
    var noise = 0.0;
    final logs = <WeightLog>[];
    for (var d = 1; d <= days; d++) {
      final date = DateTime(
        created.year,
        created.month,
        created.day + d,
        6 + random.nextInt(3),
        random.nextInt(60),
      );
      noise = (0.5 * noise + (random.nextDouble() * 2 - 1) * 0.45).clamp(
        -(maxNoiseKg - 0.05),
        maxNoiseKg - 0.05,
      );
      // Today's weigh-in sits close to the trend so the demo reads ~82.8.
      final todayNoise = d == days ? noise * 0.25 : noise;
      final kg = LosertownMath.expectedWeightOn(followed, date) + todayNoise;
      logs.add(
        WeightLog(id: uuid.v4(), date: date, weightKg: (kg * 10).round() / 10),
      );
    }

    final today = DateTime(now.year, now.month, now.day);
    return DemoData._(
      profile: profile,
      predictions: predictions,
      weightLogs: logs,
      checkpoints: [
        Checkpoint(
          id: uuid.v4(),
          label: 'Beach Trip',
          date: today.add(const Duration(days: 50)),
        ),
        Checkpoint(
          id: uuid.v4(),
          label: 'Birthday',
          date: today.add(const Duration(days: 100)),
        ),
      ],
    );
  }
}
