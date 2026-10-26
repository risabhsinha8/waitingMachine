import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/prediction_comparison.dart';

PredictionSnapshot linear() => PredictionSnapshot(
  id: 'p',
  name: 'p',
  createdAt: DateTime(2026, 1, 5),
  startWeightKg: 100,
  dailyCalories: 2000,
  activityLevel: ActivityLevel.sedentary,
  points: [
    for (var w = 0; w <= 52; w++)
      WeeklyProjectionPoint(
        weekNumber: w,
        date: DateTime(2026, 1, 5 + 7 * w),
        projectedWeightKg: 100 - w.toDouble(),
        weeklyChangeKg: w == 0 ? 0 : -1,
        dynamicTdee: 2500,
      ),
  ],
);

WeightLog log(int day, double kg, {int hour = 7}) => WeightLog(
  id: '$day-$kg',
  date: DateTime(2026, 1, 5 + day, hour),
  weightKg: kg,
);

void main() {
  test('matches the nearest weigh-in within three days of each week', () {
    final weeks = compareWeeks(linear(), [
      log(0, 100.4),
      log(8, 99.0), // a day after week 1
      log(12, 98.2), // two days before week 2, closer than day 17
      log(17, 97.9), // three days after week 2
    ]);

    expect(weeks[0].loggedWeightKg, 100.4);
    expect(weeks[0].deltaKg, closeTo(0.4, 1e-9));

    expect(weeks[1].loggedDate, DateTime(2026, 1, 13));
    // Projection on day 8 is 100 - 8/7.
    expect(weeks[1].deltaKg, closeTo(99.0 - (100 - 8 / 7), 1e-9));

    expect(weeks[2].loggedDate, DateTime(2026, 1, 17));
    expect(weeks[2].loggedWeightKg, 98.2);

    expect(weeks[3].hasLog, isFalse);
    expect(weeks.skip(3).where((w) => w.hasLog), isEmpty);
  });

  test('averages several weigh-ins on the matched day', () {
    final weeks = compareWeeks(linear(), [
      log(7, 99.2),
      log(7, 99.6, hour: 20),
    ]);
    expect(weeks[1].loggedWeightKg, closeTo(99.4, 1e-9));
  });

  test('no logs means no matches', () {
    expect(compareWeeks(linear(), []).where((w) => w.hasLog), isEmpty);
  });
}
