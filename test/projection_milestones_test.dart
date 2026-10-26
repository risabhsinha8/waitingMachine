import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/projection_milestones.dart';
import 'package:losertown/utils/units.dart';

List<WeeklyProjectionPoint> linear(double startKg, double rateKg, int weeks) =>
    [
      for (var w = 0; w <= weeks; w++)
        WeeklyProjectionPoint(
          weekNumber: w,
          date: DateTime(2026, 1, 5 + 7 * w),
          projectedWeightKg: startKg + rateKg * w,
          weeklyChangeKg: w == 0 ? 0 : rateKg,
          dynamicTdee: 2500,
        ),
    ];

Map<int, ProjectionMilestone> flagged(List<ProjectionMilestone?> ms) => {
  for (var i = 0; i < ms.length; i++)
    if (ms[i] != null) i: ms[i]!,
};

void main() {
  test('flags every 5 kg crossed on the way down', () {
    final ms = flagged(
      findMilestones(linear(100, -1, 12), unit: WeightUnit.kg),
    );
    // Starting exactly on 100 is not a crossing; reaching 95 and 90 are.
    expect(ms.keys, [5, 10]);
    expect(ms[5]!.weightKg, 95);
    expect(ms[5]!.losing, isTrue);
    expect(ms[10]!.kind, MilestoneKind.mark);
  });

  test('flags 10 lb marks for imperial users', () {
    final ms = flagged(
      findMilestones(linear(100, -1, 12), unit: WeightUnit.lbs),
    );
    // 100 kg ≈ 220.5 lbs, so week 1 (≈ 218.3 lbs) already crosses 220.
    expect(ms.keys, [1, 5, 10]);
    expect(Units.kgToLbs(ms[5]!.weightKg), closeTo(210, 1e-9));
    expect(Units.kgToLbs(ms[10]!.weightKg), closeTo(200, 1e-9));
  });

  test('target reached takes precedence over a round-number mark', () {
    final points = linear(100, -1, 12)
      ..[10] = WeeklyProjectionPoint(
        weekNumber: 10,
        date: DateTime(2026, 3, 16),
        projectedWeightKg: 90,
        weeklyChangeKg: -1,
        dynamicTdee: 2500,
      );
    final ms = flagged(
      findMilestones(points, unit: WeightUnit.kg, targetWeightKg: 90),
    );
    expect(ms[10]!.kind, MilestoneKind.target);
    expect(ms[10]!.weightKg, 90);
  });

  test('flags marks crossed on the way up', () {
    final ms = flagged(
      findMilestones(linear(78, 0.5, 10), unit: WeightUnit.kg),
    );
    expect(ms.keys, [4]);
    expect(ms[4]!.weightKg, 80);
    expect(ms[4]!.losing, isFalse);
  });

  test('flat weeks are never milestones', () {
    expect(
      findMilestones(
        linear(85, 0, 10),
        unit: WeightUnit.kg,
        targetWeightKg: 85,
      ),
      everyElement(isNull),
    );
  });
}
