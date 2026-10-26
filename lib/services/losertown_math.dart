import 'dart:collection';
import 'dart:math' as math;

import '../models/app_models.dart';

/// Core energy-balance and prediction-matching engine.
///
/// Everything here is pure and works in kilograms; unit conversion is a
/// display concern handled elsewhere.
abstract final class LosertownMath {
  /// Energy per kilogram of body-weight change used throughout the engine.
  static const double kcalPerKg = 7700;

  /// Imperial rule of thumb, for reference in lb-based UI copy.
  static const double kcalPerLb = 3500;

  static const int minProjectionWeeks = 52;
  static const int maxProjectionWeeks = 104;

  static const int emaWindowDays = 7;
  static const int rateWindowDays = 14;

  /// The rate needs at least this many days between the oldest and newest
  /// weigh-in inside the rate window, or it is reported as unknown.
  static const int minRateSpanDays = 7;

  /// Drift thresholds. Imperial users get round-number pounds rather than
  /// converted kilograms.
  static const double onTrackToleranceKg = 0.5;
  static const double driftingToleranceKg = 1.5;
  static const double onTrackToleranceLbs = 1;
  static const double driftingToleranceLbs = 3;
  static const double _kgPerLb = 0.45359237;

  /// Mifflin-St Jeor weight coefficient (kcal per kg of body weight).
  static const double _bmrKcalPerKg = 10;

  // ---------------------------------------------------------------------------
  // Energy expenditure
  // ---------------------------------------------------------------------------

  /// Mifflin-St Jeor basal metabolic rate in kcal/day.
  static double bmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required Sex sex,
  }) {
    final base = _bmrKcalPerKg * weightKg + 6.25 * heightCm - 5 * age;
    return switch (sex) {
      Sex.male => base + 5,
      Sex.female => base - 161,
    };
  }

  /// Total daily energy expenditure in kcal/day.
  static double tdee({
    required double weightKg,
    required UserProfile profile,
    required ActivityLevel activityLevel,
  }) =>
      bmr(
        weightKg: weightKg,
        heightCm: profile.heightCm,
        age: profile.age,
        sex: profile.sex,
      ) *
      activityLevel.multiplier;

  // ---------------------------------------------------------------------------
  // Projection
  // ---------------------------------------------------------------------------

  /// Projects weekly weight from [startWeightKg] at a fixed [dailyCalories].
  ///
  /// TDEE is recalculated from each week's resulting weight, so the deficit
  /// (and the rate of loss) shrinks as the body gets lighter. When
  /// [targetWeightKg] is reached the projection holds there, assuming the user
  /// switches to maintenance.
  ///
  /// Returns `weeks + 1` points: week 0 is the anchor at [startDate].
  static List<WeeklyProjectionPoint> generateProjection({
    required UserProfile profile,
    required double startWeightKg,
    required double dailyCalories,
    required ActivityLevel activityLevel,
    required DateTime startDate,
    int weeks = minProjectionWeeks,
    double? targetWeightKg,
  }) {
    if (weeks < minProjectionWeeks || weeks > maxProjectionWeeks) {
      throw RangeError.range(
        weeks,
        minProjectionWeeks,
        maxProjectionWeeks,
        'weeks',
      );
    }
    if (startWeightKg <= 0) {
      throw ArgumentError.value(startWeightKg, 'startWeightKg', 'must be > 0');
    }
    if (dailyCalories <= 0) {
      throw ArgumentError.value(dailyCalories, 'dailyCalories', 'must be > 0');
    }

    double tdeeAt(double weightKg) => tdee(
      weightKg: weightKg,
      profile: profile,
      activityLevel: activityLevel,
    );

    final anchor = _localDay(startDate);
    var weight = startWeightKg;
    var reachedTarget = false;
    final points = <WeeklyProjectionPoint>[
      WeeklyProjectionPoint(
        weekNumber: 0,
        date: anchor,
        projectedWeightKg: weight,
        weeklyChangeKg: 0,
        dynamicTdee: tdeeAt(weight),
      ),
    ];

    for (var week = 1; week <= weeks; week++) {
      var next = weight;
      if (!reachedTarget) {
        next = weight + (dailyCalories - tdeeAt(weight)) * 7 / kcalPerKg;
        final target = targetWeightKg;
        // Reached (or crossed) the target this week.
        if (target != null && (weight - target) * (next - target) <= 0) {
          next = target;
          reachedTarget = true;
        }
      }
      points.add(
        WeeklyProjectionPoint(
          weekNumber: week,
          date: DateTime(anchor.year, anchor.month, anchor.day + 7 * week),
          projectedWeightKg: next,
          weeklyChangeKg: next - weight,
          dynamicTdee: tdeeAt(next),
        ),
      );
      weight = next;
    }
    return points;
  }

  /// What [prediction] says the user should weigh on [date], linearly
  /// interpolated between weekly points and clamped to the projected range.
  static double expectedWeightOn(
    PredictionSnapshot prediction,
    DateTime date,
  ) => _sample(prediction, date).weightKg;

  /// The prediction's weekly rate of change for the week containing [date].
  static double expectedWeeklyRateOn(
    PredictionSnapshot prediction,
    DateTime date,
  ) => _sample(prediction, date).weeklyRateKg;

  static ({double weightKg, double weeklyRateKg, double tdee}) _sample(
    PredictionSnapshot prediction,
    DateTime date,
  ) {
    final pts = prediction.points;
    if (pts.isEmpty) {
      throw StateError('Prediction ${prediction.id} has no points');
    }
    if (pts.length == 1) {
      return (
        weightKg: pts.first.projectedWeightKg,
        weeklyRateKg: 0,
        tdee: pts.first.dynamicTdee,
      );
    }
    final lastWeek = (pts.length - 1).toDouble();
    final weeks = (_daysBetween(prediction.createdAt, date) / 7).clamp(
      0.0,
      lastWeek,
    );
    final i = math.min(weeks.floor(), pts.length - 2);
    final t = weeks - i;
    final a = pts[i];
    final b = pts[i + 1];
    return (
      weightKg: _lerp(a.projectedWeightKg, b.projectedWeightKg, t),
      weeklyRateKg: b.projectedWeightKg - a.projectedWeightKg,
      tdee: _lerp(a.dynamicTdee, b.dynamicTdee, t),
    );
  }

  // ---------------------------------------------------------------------------
  // Smoothing
  // ---------------------------------------------------------------------------

  /// Exponential moving average over daily weigh-ins.
  ///
  /// Multiple logs on the same day are averaged first. Uses the standard
  /// `alpha = 2 / (N + 1)` and is gap-aware: a gap of `d` days applies
  /// `1 - (1 - alpha)^d`, i.e. the same decay as `d` missed daily updates.
  static List<SmoothedWeight> smoothWeights(
    List<WeightLog> logs, {
    int windowDays = emaWindowDays,
  }) {
    if (logs.isEmpty) return const [];

    final byDay = SplayTreeMap<DateTime, List<double>>();
    for (final log in logs) {
      byDay.putIfAbsent(_utcDay(log.date), () => []).add(log.weightKg);
    }

    final alpha = 2 / (windowDays + 1);
    final result = <SmoothedWeight>[];
    double? ema;
    DateTime? previousDay;
    for (final MapEntry(key: day, value: weights) in byDay.entries) {
      final raw = weights.reduce((a, b) => a + b) / weights.length;
      if (ema == null) {
        ema = raw;
      } else {
        final gapDays = day.difference(previousDay!).inDays;
        final effectiveAlpha = 1 - math.pow(1 - alpha, gapDays);
        ema += effectiveAlpha * (raw - ema);
      }
      previousDay = day;
      result.add(
        SmoothedWeight(
          date: DateTime(day.year, day.month, day.day),
          rawWeightKg: raw,
          smoothedWeightKg: ema,
        ),
      );
    }
    return result;
  }

  /// Least-squares slope of the smoothed weight over the trailing
  /// [windowDays], in kg per week. Null if there isn't enough data.
  static double? weeklyRateKg(
    List<SmoothedWeight> smoothed, {
    int windowDays = rateWindowDays,
  }) {
    if (smoothed.length < 2) return null;
    final end = smoothed.last.date;
    final window = smoothed
        .where((s) => _daysBetween(s.date, end) < windowDays)
        .toList();
    if (window.length < 2) return null;

    final xs = [for (final s in window) -_daysBetween(s.date, end).toDouble()];
    if (xs.last - xs.first < minRateSpanDays) return null;
    final ys = [for (final s in window) s.smoothedWeightKg];

    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var covariance = 0.0;
    var variance = 0.0;
    for (var i = 0; i < xs.length; i++) {
      covariance += (xs[i] - meanX) * (ys[i] - meanY);
      variance += (xs[i] - meanX) * (xs[i] - meanX);
    }
    return covariance / variance * 7;
  }

  // ---------------------------------------------------------------------------
  // Matching
  // ---------------------------------------------------------------------------

  static AdherenceStatus classifyAdherence(
    double deltaKg, {
    WeightUnit unit = WeightUnit.kg,
  }) {
    final (onTrack, drifting) = switch (unit) {
      WeightUnit.kg => (onTrackToleranceKg, driftingToleranceKg),
      WeightUnit.lbs => (
        onTrackToleranceLbs * _kgPerLb,
        driftingToleranceLbs * _kgPerLb,
      ),
    };
    final magnitude = deltaKg.abs();
    if (magnitude <= onTrack) return AdherenceStatus.onTrack;
    if (magnitude <= drifting) return AdherenceStatus.drifting;
    return AdherenceStatus.offCourse;
  }

  /// Compares every prediction against the user's smoothed weight and recent
  /// pace, as of the most recent weigh-in. Returns null if there are no logs.
  ///
  /// The comparison day is the latest log's date rather than the wall clock,
  /// so a stale weigh-in isn't compared against a projection that has moved
  /// on since.
  static PredictionMatchResult? evaluatePredictions(
    List<PredictionSnapshot> predictions,
    List<WeightLog> logs, {
    WeightUnit unit = WeightUnit.kg,
  }) {
    final smoothed = smoothWeights(logs);
    if (smoothed.isEmpty) return null;

    final asOf = smoothed.last.date;
    final current = smoothed.last.smoothedWeightKg;
    final actualRate = weeklyRateKg(smoothed);

    final evaluations = [
      for (final p in predictions)
        if (p.points.isNotEmpty) _evaluate(p, asOf, current, actualRate, unit),
    ];

    int byPosition(PredictionEvaluation a, PredictionEvaluation b) =>
        a.deltaFromActualKg.abs().compareTo(b.deltaFromActualKg.abs());
    int byPace(PredictionEvaluation a, PredictionEvaluation b) =>
        a.paceDeltaKg!.abs().compareTo(b.paceDeltaKg!.abs());

    return PredictionMatchResult(
      asOf: asOf,
      currentWeightKg: current,
      actualWeeklyRateKg: actualRate,
      byPosition: [...evaluations]
        ..sort((a, b) {
          final c = byPosition(a, b);
          return c != 0 || actualRate == null ? c : byPace(a, b);
        }),
      byPace: actualRate == null
          ? const []
          : ([...evaluations]..sort((a, b) {
              final c = byPace(a, b);
              return c != 0 ? c : byPosition(a, b);
            })),
    );
  }

  static PredictionEvaluation _evaluate(
    PredictionSnapshot prediction,
    DateTime asOf,
    double actualWeightKg,
    double? actualWeeklyRateKg,
    WeightUnit unit,
  ) {
    final sample = _sample(prediction, asOf);
    final delta = actualWeightKg - sample.weightKg;
    return PredictionEvaluation(
      predictionId: prediction.id,
      expectedWeightTodayKg: sample.weightKg,
      deltaFromActualKg: delta,
      adherenceStatus: classifyAdherence(delta, unit: unit),
      expectedWeeklyRateKg: sample.weeklyRateKg,
      paceDeltaKg: actualWeeklyRateKg == null
          ? null
          : actualWeeklyRateKg - sample.weeklyRateKg,
      impliedDailyCalories: actualWeeklyRateKg == null
          ? null
          : _impliedDailyCalories(
              prediction,
              sample.tdee,
              delta,
              actualWeeklyRateKg,
            ),
    );
  }

  /// Intake that would produce [actualWeeklyRateKg] at the user's actual
  /// weight. Mifflin-St Jeor is linear in weight, so the snapshot's TDEE at
  /// the expected weight can be shifted to the actual weight exactly, using
  /// the profile the snapshot was generated with.
  static double _impliedDailyCalories(
    PredictionSnapshot prediction,
    double expectedTdee,
    double deltaKg,
    double actualWeeklyRateKg,
  ) {
    final actualTdee =
        expectedTdee +
        _bmrKcalPerKg * prediction.activityLevel.multiplier * deltaKg;
    return actualTdee + actualWeeklyRateKg * kcalPerKg / 7;
  }

  // ---------------------------------------------------------------------------
  // Date helpers
  // ---------------------------------------------------------------------------

  static DateTime _localDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Calendar day as UTC midnight, so day arithmetic ignores DST shifts.
  static DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static int _daysBetween(DateTime from, DateTime to) =>
      _utcDay(to).difference(_utcDay(from)).inDays;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
