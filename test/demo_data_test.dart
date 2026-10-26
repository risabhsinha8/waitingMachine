import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/demo_data.dart';
import 'package:losertown/services/losertown_math.dart';

final now = DateTime(2026, 10, 26, 9);

void main() {
  final demo = DemoData.build(now: now);
  final followed = demo.predictions.firstWhere(
    (p) => p.name == DemoData.followedName,
  );

  test('three predictions locked in 30 days ago at 85 kg', () {
    expect(demo.predictions.map((p) => p.name), [
      'Aggressive Cut (1500 kcal)',
      'Sustainable 1850 kcal',
      'Lazy 2150 kcal',
    ]);
    expect(demo.predictions.map((p) => p.dailyCalories), [1500, 1850, 2150]);
    for (final p in demo.predictions) {
      expect(p.createdAt, DateTime(2026, 9, 26, 8));
      expect(p.startWeightKg, 85);
      expect(p.points.first.projectedWeightKg, 85);
    }
  });

  test('30 daily weigh-ins ending today', () {
    expect(demo.weightLogs, hasLength(30));
    final days = demo.weightLogs
        .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
        .toSet();
    expect(days, hasLength(30));
    expect(days.first, DateTime(2026, 9, 27));
    expect(days.last, DateTime(2026, 10, 26));
  });

  test('weigh-ins follow the sustainable plan within ±0.6 kg', () {
    final deviations = [
      for (final l in demo.weightLogs)
        l.weightKg - LosertownMath.expectedWeightOn(followed, l.date),
    ];
    expect(deviations.every((d) => d.abs() <= DemoData.maxNoiseKg), isTrue);
    // Real water-weight noise, not a flat line.
    expect(deviations.where((d) => d.abs() > 0.2), isNotEmpty);
  });

  test('lands at ~82.8 kg today', () {
    expect(LosertownMath.expectedWeightOn(followed, now), closeTo(82.8, 0.1));
    expect(demo.weightLogs.last.weightKg, closeTo(82.8, 0.2));
  });

  test('the sustainable plan wins both position and pace matching', () {
    final result = LosertownMath.evaluatePredictions(
      demo.predictions,
      demo.weightLogs,
    )!;
    expect(result.byPosition.first.predictionId, followed.id);
    expect(result.byPace.first.predictionId, followed.id);
    expect(result.byPosition.first.adherenceStatus, AdherenceStatus.onTrack);
  });

  test('is deterministic and keeps the display unit', () {
    final again = DemoData.build(now: now, unit: WeightUnit.lbs);
    expect(
      again.weightLogs.map((l) => l.weightKg),
      demo.weightLogs.map((l) => l.weightKg),
    );
    expect(again.profile.preferredUnit, WeightUnit.lbs);
  });

  test('pins two upcoming checkpoints', () {
    expect(demo.checkpoints.map((c) => c.label), ['Beach Trip', 'Birthday']);
    expect(demo.checkpoints.first.date, DateTime(2026, 12, 15));
  });
}
