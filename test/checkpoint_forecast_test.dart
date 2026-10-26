import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/checkpoint_forecast.dart';
import 'package:losertown/services/losertown_math.dart';

const profile = UserProfile(heightCm: 175, age: 38, sex: Sex.male);
final now = DateTime(2026, 10, 26, 9);
final created = DateTime(2026, 9, 26, 8);

PredictionSnapshot plan(double kcal) => PredictionSnapshot(
  id: 'p$kcal',
  name: 'p$kcal',
  createdAt: created,
  startWeightKg: 85,
  dailyCalories: kcal,
  activityLevel: ActivityLevel.lightlyActive,
  points: LosertownMath.generateProjection(
    profile: profile,
    startWeightKg: 85,
    dailyCalories: kcal,
    activityLevel: ActivityLevel.lightlyActive,
    startDate: created,
  ),
);

Checkpoint at(String label, DateTime date) =>
    Checkpoint(id: label, label: label, date: date);

void main() {
  final beach = at('Beach', DateTime(2026, 12, 15));

  test('upcoming dates project the plan forward from today\'s trend', () {
    final aggressive = plan(1500);
    // The user drifted: they're at 83.5 kg, not where the plan expected.
    final forecast = forecastCheckpoints(
      aggressive,
      [beach],
      now: now,
      profile: profile,
      currentWeightKg: 83.5,
    ).single;

    final fromToday = PredictionSnapshot(
      id: 'x',
      name: 'x',
      createdAt: DateTime(2026, 10, 26),
      startWeightKg: 83.5,
      dailyCalories: 1500,
      activityLevel: ActivityLevel.lightlyActive,
      points: LosertownMath.generateProjection(
        profile: profile,
        startWeightKg: 83.5,
        dailyCalories: 1500,
        activityLevel: ActivityLevel.lightlyActive,
        startDate: DateTime(2026, 10, 26),
      ),
    );
    expect(
      forecast.weightKg,
      closeTo(LosertownMath.expectedWeightOn(fromToday, beach.date), 1e-9),
    );
    // Heavier than the original timeline promised, since they drifted.
    expect(
      forecast.weightKg,
      greaterThan(LosertownMath.expectedWeightOn(aggressive, beach.date)),
    );
    expect(forecast.isPast, isFalse);
  });

  test('without weigh-ins it reads the saved timeline', () {
    final p = plan(1850);
    final forecast = forecastCheckpoints(p, [beach], now: now).single;
    expect(forecast.weightKg, LosertownMath.expectedWeightOn(p, beach.date));
  });

  test('past dates report what the plan said back then', () {
    final p = plan(1850);
    final forecast = forecastCheckpoints(
      p,
      [at('Last week', DateTime(2026, 10, 19))],
      now: now,
      profile: profile,
      currentWeightKg: 83,
    ).single;
    expect(forecast.isPast, isTrue);
    expect(
      forecast.weightKg,
      LosertownMath.expectedWeightOn(p, DateTime(2026, 10, 19)),
    );
  });

  test('dates beyond two years have no forecast', () {
    final forecast = forecastCheckpoints(
      plan(1850),
      [at('Far', DateTime(2029, 1, 1))],
      now: now,
      profile: profile,
      currentWeightKg: 83,
    ).single;
    expect(forecast.weightKg, isNull);
  });

  test('a later checkpoint extends the forward horizon', () {
    final forecast = forecastCheckpoints(
      plan(1850),
      [at('In 80 weeks', DateTime(2028, 5, 8))],
      now: now,
      profile: profile,
      currentWeightKg: 83,
    ).single;
    expect(forecast.weightKg, isNotNull);
  });
}
