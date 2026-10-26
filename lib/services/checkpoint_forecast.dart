import '../models/app_models.dart';
import 'losertown_math.dart';

/// What a prediction says the user will weigh on one checkpoint date.
class CheckpointForecast {
  const CheckpointForecast({
    required this.checkpoint,
    required this.weightKg,
    this.isPast = false,
  });

  final Checkpoint checkpoint;

  /// Null when the date is beyond the furthest projection the engine makes.
  final double? weightKg;

  /// The date has passed; [weightKg] is what the prediction said back then.
  final bool isPast;
}

/// Forecasts [checkpoints] for [prediction].
///
/// For upcoming dates this answers "if I follow this plan from today": it
/// projects the plan's calories and activity forward from the user's current
/// trend weight, so a plan they've drifted from isn't quoted at a weight
/// they can no longer reach. Without weigh-ins (or a profile), or for dates
/// already past, it falls back to the prediction's own saved timeline.
List<CheckpointForecast> forecastCheckpoints(
  PredictionSnapshot prediction,
  List<Checkpoint> checkpoints, {
  required DateTime now,
  UserProfile? profile,
  double? currentWeightKg,
}) {
  if (checkpoints.isEmpty || prediction.points.isEmpty) return const [];
  final today = DateTime(now.year, now.month, now.day);
  final upcoming = [
    for (final c in checkpoints)
      if (!c.date.isBefore(today)) c,
  ];

  // The forward timeline from today, long enough for the latest checkpoint.
  PredictionSnapshot? forward;
  if (profile != null && currentWeightKg != null && upcoming.isNotEmpty) {
    final latest = upcoming
        .map((c) => c.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final weeks = (latest.difference(today).inDays / 7).ceil().clamp(
      LosertownMath.minProjectionWeeks,
      LosertownMath.maxProjectionWeeks,
    );
    forward = prediction.copyWith(
      createdAt: today,
      startWeightKg: currentWeightKg,
      points: LosertownMath.generateProjection(
        profile: profile,
        startWeightKg: currentWeightKg,
        dailyCalories: prediction.dailyCalories,
        activityLevel: prediction.activityLevel,
        startDate: today,
        weeks: weeks,
        targetWeightKg: prediction.targetWeightKg,
      ),
    );
  }

  return [
    for (final c in checkpoints)
      if (c.date.isBefore(today))
        CheckpointForecast(
          checkpoint: c,
          weightKg: _within(prediction, c.date),
          isPast: true,
        )
      else
        CheckpointForecast(
          checkpoint: c,
          weightKg: _within(forward ?? prediction, c.date),
        ),
  ];
}

/// The projection on [date], or null past the end of its horizon.
double? _within(PredictionSnapshot timeline, DateTime date) =>
    date.isAfter(timeline.points.last.date)
    ? null
    : LosertownMath.expectedWeightOn(timeline, date);
