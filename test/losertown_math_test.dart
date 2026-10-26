import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/losertown_math.dart';

const profile = UserProfile(heightCm: 180, age: 35, sex: Sex.male);
const activity = ActivityLevel.moderatelyActive;
final start = DateTime(2026, 1, 5);

DateTime dayAt(int day) => DateTime(2026, 1, 5 + day, 7, 30);

PredictionSnapshot snapshot(
  String id,
  double dailyCalories, {
  double startWeightKg = 100,
  double? targetWeightKg,
}) => PredictionSnapshot(
  id: id,
  name: id,
  createdAt: start,
  startWeightKg: startWeightKg,
  dailyCalories: dailyCalories,
  activityLevel: activity,
  targetWeightKg: targetWeightKg,
  points: LosertownMath.generateProjection(
    profile: profile,
    startWeightKg: startWeightKg,
    dailyCalories: dailyCalories,
    activityLevel: activity,
    startDate: start,
    targetWeightKg: targetWeightKg,
  ),
);

/// A hand-built snapshot with a constant weekly rate (no TDEE dynamics).
PredictionSnapshot linearSnapshot(String id, double startKg, double rateKg) =>
    PredictionSnapshot(
      id: id,
      name: id,
      createdAt: start,
      startWeightKg: startKg,
      dailyCalories: 2000,
      activityLevel: activity,
      points: [
        for (var w = 0; w <= 52; w++)
          WeeklyProjectionPoint(
            weekNumber: w,
            date: DateTime(2026, 1, 5 + 7 * w),
            projectedWeightKg: startKg + rateKg * w,
            weeklyChangeKg: w == 0 ? 0 : rateKg,
            dynamicTdee: 3000,
          ),
      ],
    );

WeightLog log(int day, double kg) =>
    WeightLog(id: 'log$day-$kg', date: dayAt(day), weightKg: kg);

void main() {
  group('BMR / TDEE', () {
    test('Mifflin-St Jeor matches reference values', () {
      expect(
        LosertownMath.bmr(weightKg: 80, heightCm: 180, age: 30, sex: Sex.male),
        closeTo(1780, 1e-9),
      );
      expect(
        LosertownMath.bmr(
          weightKg: 60,
          heightCm: 165,
          age: 25,
          sex: Sex.female,
        ),
        closeTo(1345.25, 1e-9),
      );
    });

    test('TDEE applies the activity multiplier', () {
      // BMR = 1000 + 1125 - 175 + 5 = 1955
      for (final level in ActivityLevel.values) {
        expect(
          LosertownMath.tdee(
            weightKg: 100,
            profile: profile,
            activityLevel: level,
          ),
          closeTo(1955 * level.multiplier, 1e-9),
        );
      }
    });
  });

  group('generateProjection', () {
    final points = snapshot('p', 2000).points;
    // Weight at which TDEE == intake; the projection decays towards it.
    final equilibriumKg = (2000 / activity.multiplier - 1125 + 175 - 5) / 10;
    final decayPerWeek = 10 * activity.multiplier * 7 / LosertownMath.kcalPerKg;

    test('returns weeks + 1 weekly points anchored at the start date', () {
      expect(points, hasLength(53));
      expect(points.first.weekNumber, 0);
      expect(points.first.date, start);
      expect(points.first.projectedWeightKg, 100);
      expect(points[1].date, DateTime(2026, 1, 12));
      expect(points.last.date, DateTime(2027, 1, 4));
    });

    test('first week uses the full starting deficit at 7700 kcal/kg', () {
      final tdee0 = 1955 * activity.multiplier;
      expect(points.first.dynamicTdee, closeTo(tdee0, 1e-9));
      expect(
        points[1].weeklyChangeKg,
        closeTo((2000 - tdee0) * 7 / 7700, 1e-9),
      );
    });

    test('TDEE is recalculated weekly so loss slows as weight drops', () {
      for (var i = 1; i < points.length; i++) {
        expect(points[i].dynamicTdee, lessThan(points[i - 1].dynamicTdee));
        expect(
          points[i].dynamicTdee,
          closeTo(
            LosertownMath.tdee(
              weightKg: points[i].projectedWeightKg,
              profile: profile,
              activityLevel: activity,
            ),
            1e-9,
          ),
        );
        if (i > 1) {
          // Still losing, but by less each week.
          expect(points[i].weeklyChangeKg, lessThan(0));
          expect(
            points[i].weeklyChangeKg,
            greaterThan(points[i - 1].weeklyChangeKg),
          );
        }
      }
    });

    test('follows the closed-form geometric decay towards equilibrium', () {
      for (final p in points) {
        final expected =
            equilibriumKg +
            (100 - equilibriumKg) * math.pow(1 - decayPerWeek, p.weekNumber);
        expect(p.projectedWeightKg, closeTo(expected, 1e-9));
      }
    });

    test('loses less than a static-TDEE projection would', () {
      final staticWeeklyLoss = (1955 * activity.multiplier - 2000) * 7 / 7700;
      final staticFinal = 100 - staticWeeklyLoss * 52;
      expect(points.last.projectedWeightKg, greaterThan(staticFinal + 1));
    });

    test('holds at the target weight once reached', () {
      final pts = snapshot('t', 2000, targetWeightKg: 90).points;
      final reached = pts.indexWhere((p) => p.projectedWeightKg == 90);
      expect(reached, greaterThan(0));
      expect(pts[reached - 1].projectedWeightKg, greaterThan(90));
      for (final p in pts.skip(reached + 1)) {
        expect(p.projectedWeightKg, 90);
        expect(p.weeklyChangeKg, 0);
        expect(p.dynamicTdee, pts[reached].dynamicTdee);
      }
    });

    test('supports a surplus towards a higher target', () {
      final pts = snapshot('bulk', 3500, targetWeightKg: 105).points;
      expect(pts[1].weeklyChangeKg, greaterThan(0));
      expect(pts.last.projectedWeightKg, 105);
      expect(pts.map((p) => p.projectedWeightKg).reduce(math.max), 105);
    });

    test('rejects horizons outside 52-104 weeks', () {
      List<WeeklyProjectionPoint> gen(int weeks) =>
          LosertownMath.generateProjection(
            profile: profile,
            startWeightKg: 100,
            dailyCalories: 2000,
            activityLevel: activity,
            startDate: start,
            weeks: weeks,
          );
      expect(() => gen(51), throwsRangeError);
      expect(() => gen(105), throwsRangeError);
      expect(gen(104), hasLength(105));
    });
  });

  group('expectedWeightOn', () {
    final p = linearSnapshot('lin', 100, -1);

    test('interpolates within a week', () {
      expect(LosertownMath.expectedWeightOn(p, dayAt(0)), 100);
      expect(LosertownMath.expectedWeightOn(p, dayAt(7)), 99);
      expect(
        LosertownMath.expectedWeightOn(p, dayAt(10)),
        closeTo(98.571, 1e-3),
      );
      expect(LosertownMath.expectedWeeklyRateOn(p, dayAt(10)), -1);
    });

    test('clamps before the anchor and after the horizon', () {
      expect(LosertownMath.expectedWeightOn(p, dayAt(-30)), 100);
      expect(LosertownMath.expectedWeightOn(p, dayAt(1000)), 48);
    });
  });

  group('EMA smoothing', () {
    test('constant input stays constant', () {
      final smoothed = LosertownMath.smoothWeights([
        for (var d = 0; d < 10; d++) log(d, 80),
      ]);
      expect(smoothed.map((s) => s.smoothedWeightKg), everyElement(80));
    });

    test('dampens a one-day water-weight spike', () {
      final logs = [for (var d = 0; d < 10; d++) log(d, d == 5 ? 82 : 80)];
      final smoothed = LosertownMath.smoothWeights(logs);
      // alpha = 2 / (7 + 1) = 0.25
      expect(smoothed[5].rawWeightKg, 82);
      expect(smoothed[5].smoothedWeightKg, closeTo(80.5, 1e-9));
      expect(smoothed[6].smoothedWeightKg, closeTo(80.375, 1e-9));
      // The spike's residual decays by (1 - alpha) each following day.
      expect(
        smoothed.last.smoothedWeightKg,
        closeTo(80 + 0.5 * math.pow(0.75, 4), 1e-9),
      );
    });

    test('applies compounded decay across gaps between weigh-ins', () {
      final smoothed = LosertownMath.smoothWeights([log(0, 80), log(7, 73)]);
      final alpha = 1 - math.pow(0.75, 7);
      expect(smoothed.last.smoothedWeightKg, closeTo(80 - 7 * alpha, 1e-9));
    });

    test('sorts input and averages same-day weigh-ins', () {
      final smoothed = LosertownMath.smoothWeights([
        log(1, 81),
        WeightLog(id: 'x', date: DateTime(2026, 1, 5, 21), weightKg: 80.6),
        log(0, 80),
      ]);
      expect(smoothed, hasLength(2));
      expect(smoothed.first.date, DateTime(2026, 1, 5));
      expect(smoothed.first.rawWeightKg, closeTo(80.3, 1e-9));
      expect(smoothed.last.smoothedWeightKg, closeTo(80.3 + 0.25 * 0.7, 1e-9));
    });

    test('empty input yields no points', () {
      expect(LosertownMath.smoothWeights([]), isEmpty);
    });
  });

  group('weeklyRateKg', () {
    test('recovers a steady linear trend from the smoothed series', () {
      final smoothed = LosertownMath.smoothWeights([
        for (var d = 0; d < 28; d++) log(d, 90 - 0.1 * d),
      ]);
      expect(LosertownMath.weeklyRateKg(smoothed), closeTo(-0.7, 0.02));
    });

    test('is unknown when the window spans less than a week', () {
      final smoothed = LosertownMath.smoothWeights([
        for (var d = 0; d < 5; d++) log(d, 90 - 0.1 * d),
      ]);
      expect(LosertownMath.weeklyRateKg(smoothed), isNull);
    });
  });

  group('classifyAdherence', () {
    test('uses 0.5 / 1.5 kg bands', () {
      expect(LosertownMath.classifyAdherence(0.48), AdherenceStatus.onTrack);
      expect(LosertownMath.classifyAdherence(-1.4), AdherenceStatus.drifting);
      expect(LosertownMath.classifyAdherence(1.6), AdherenceStatus.offCourse);
    });

    test('uses 1 / 3 lb bands for imperial users', () {
      // 0.48 kg ≈ 1.06 lb and 1.4 kg ≈ 3.09 lb.
      expect(
        LosertownMath.classifyAdherence(0.48, unit: WeightUnit.lbs),
        AdherenceStatus.drifting,
      );
      expect(
        LosertownMath.classifyAdherence(1.4, unit: WeightUnit.lbs),
        AdherenceStatus.offCourse,
      );
      expect(
        LosertownMath.classifyAdherence(0.45, unit: WeightUnit.lbs),
        AdherenceStatus.onTrack,
      );
    });
  });

  group('evaluatePredictions', () {
    final aggressive = snapshot('aggressive', 1500);
    final moderate = snapshot('moderate', 2000);
    final gentle = snapshot('gentle', 2500);
    final predictions = [aggressive, gentle, moderate];

    /// Daily logs that follow [p] for [days] with zero-mean daily noise.
    List<WeightLog> followLogs(PredictionSnapshot p, int days) {
      const noise = [0.4, -0.3, 0.1, -0.2, 0.5, -0.4, -0.1];
      return [
        for (var d = 0; d <= days; d++)
          log(d, LosertownMath.expectedWeightOn(p, dayAt(d)) + noise[d % 7]),
      ];
    }

    test('ranks the followed prediction first by position and pace', () {
      final result = LosertownMath.evaluatePredictions(
        predictions,
        followLogs(moderate, 56),
      )!;

      expect(result.asOf, DateTime(2026, 3, 2));
      expect(result.byPosition.first.predictionId, 'moderate');
      expect(result.byPace.first.predictionId, 'moderate');

      final best = result.byPosition.first;
      expect(best.adherenceStatus, AdherenceStatus.onTrack);
      expect(best.deltaFromActualKg.abs(), lessThan(0.6));
      expect(best.paceDeltaKg!.abs(), lessThan(0.05));
      expect(best.impliedDailyCalories, closeTo(2000, 75));

      final others = result.byPosition.skip(1);
      expect(
        others.map((e) => e.adherenceStatus),
        everyElement(AdherenceStatus.offCourse),
      );
    });

    test('implied intake reflects eating more than the plan', () {
      final result = LosertownMath.evaluatePredictions([
        moderate,
      ], followLogs(gentle, 56))!;
      final e = result.byPosition.single;
      expect(e.deltaFromActualKg, greaterThan(2.5));
      expect(e.paceDeltaKg, greaterThan(0));
      expect(e.impliedDailyCalories, closeTo(2500, 75));
    });

    test('a single water-weight spike does not change the best match', () {
      final logs = followLogs(moderate, 56)..add(log(57, 95));
      final result = LosertownMath.evaluatePredictions(predictions, logs)!;
      expect(result.byPosition.first.predictionId, 'moderate');
      expect(result.byPace.first.predictionId, 'moderate');
    });

    test('position and pace rankings can disagree', () {
      final steep = linearSnapshot('steep', 100, -1); // 96.0 at day 28
      final slow = linearSnapshot('slow', 98, -0.25); // 97.0 at day 28
      final logs = [for (var d = 0; d <= 28; d++) log(d, 97.2 - 0.25 / 7 * d)];
      final result = LosertownMath.evaluatePredictions([slow, steep], logs)!;

      expect(result.actualWeeklyRateKg, closeTo(-0.25, 0.01));
      expect(result.byPosition.map((e) => e.predictionId), ['steep', 'slow']);
      expect(result.byPace.map((e) => e.predictionId), ['slow', 'steep']);
      final steepEval = result.byPosition.first;
      expect(steepEval.expectedWeightTodayKg, closeTo(96, 1e-9));
      expect(steepEval.expectedWeeklyRateKg, -1);
      expect(steepEval.paceDeltaKg, closeTo(0.75, 0.01));
    });

    test('compares at the latest weigh-in date, not the wall clock', () {
      final result = LosertownMath.evaluatePredictions([
        moderate,
      ], followLogs(moderate, 21))!;
      expect(result.asOf, DateTime(2026, 1, 26));
      expect(
        result.byPosition.single.expectedWeightTodayKg,
        closeTo(moderate.points[3].projectedWeightKg, 1e-9),
      );
    });

    test('reports pace as unknown with too little history', () {
      final result = LosertownMath.evaluatePredictions(
        predictions,
        followLogs(moderate, 3),
      )!;
      expect(result.actualWeeklyRateKg, isNull);
      expect(result.byPace, isEmpty);
      expect(result.byPosition, hasLength(3));
      expect(result.byPosition.first.paceDeltaKg, isNull);
      expect(result.byPosition.first.impliedDailyCalories, isNull);
    });

    test('returns null with no logs', () {
      expect(LosertownMath.evaluatePredictions(predictions, []), isNull);
    });
  });
}
