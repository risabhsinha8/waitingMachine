import '../models/app_models.dart';
import 'losertown_math.dart';

/// One projected week paired with the weigh-in closest to it, if any.
class WeekComparison {
  const WeekComparison({
    required this.point,
    this.loggedDate,
    this.loggedWeightKg,
    this.deltaKg,
  });

  final WeeklyProjectionPoint point;

  /// Day of the matched weigh-in, which may differ from [point]'s date.
  final DateTime? loggedDate;

  /// Mean of the weigh-ins on [loggedDate].
  final double? loggedWeightKg;

  /// `logged - projected`, with the projection interpolated to [loggedDate].
  final double? deltaKg;

  bool get hasLog => loggedWeightKg != null;
}

/// Pairs each week of [prediction] with the nearest logged day within
/// [windowDays] either side of that week's date. Windows of ±3 days tile the
/// week exactly, so no weigh-in is matched to two weeks.
List<WeekComparison> compareWeeks(
  PredictionSnapshot prediction,
  List<WeightLog> logs, {
  int windowDays = 3,
}) {
  // Reuses smoothing purely to collapse logs to one mean per calendar day.
  final days = LosertownMath.smoothWeights(logs);
  return [
    for (final point in prediction.points)
      _compare(prediction, point, days, windowDays),
  ];
}

WeekComparison _compare(
  PredictionSnapshot prediction,
  WeeklyProjectionPoint point,
  List<SmoothedWeight> days,
  int windowDays,
) {
  SmoothedWeight? best;
  var bestDistance = windowDays + 1;
  for (final day in days) {
    final distance = _daysBetween(point.date, day.date).abs();
    if (distance < bestDistance) {
      best = day;
      bestDistance = distance;
    }
  }
  if (best == null) return WeekComparison(point: point);
  return WeekComparison(
    point: point,
    loggedDate: best.date,
    loggedWeightKg: best.rawWeightKg,
    deltaKg:
        best.rawWeightKg -
        LosertownMath.expectedWeightOn(prediction, best.date),
  );
}

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
