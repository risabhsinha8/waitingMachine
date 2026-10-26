import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';

/// Minimum weigh-ins before the Arena claims to know which timeline you're on.
const int minLogsForMatch = 2;

/// High-contrast summary of which saved prediction reality is tracking.
class TimelineHero extends StatelessWidget {
  const TimelineHero({
    super.key,
    required this.evaluation,
    required this.predictions,
    required this.logCount,
    required this.unit,
    required this.now,
    required this.onCreatePrediction,
    required this.onLogWeight,
    this.archivedCount = 0,
  });

  final PredictionMatchResult? evaluation;

  /// The Arena's (active) predictions.
  final List<PredictionSnapshot> predictions;
  final int archivedCount;
  final int logCount;
  final WeightUnit unit;
  final DateTime now;
  final VoidCallback onCreatePrediction;
  final VoidCallback onLogWeight;

  @override
  Widget build(BuildContext context) {
    final result = evaluation;
    if (predictions.isEmpty ||
        logCount < minLogsForMatch ||
        result == null ||
        result.byPosition.isEmpty) {
      return _EmptyHero(
        hasPredictions: predictions.isNotEmpty,
        archivedCount: archivedCount,
        logCount: logCount,
        onCreatePrediction: onCreatePrediction,
        onLogWeight: onLogWeight,
      );
    }
    return _MatchHero(
      result: result,
      predictions: {for (final p in predictions) p.id: p},
      logCount: logCount,
      unit: unit,
      now: now,
    );
  }
}

class _MatchHero extends StatelessWidget {
  const _MatchHero({
    required this.result,
    required this.predictions,
    required this.logCount,
    required this.unit,
    required this.now,
  });

  final PredictionMatchResult result;
  final Map<String, PredictionSnapshot> predictions;
  final int logCount;
  final WeightUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onHero = scheme.onPrimary;
    final muted = onHero.withValues(alpha: 0.8);

    final closest = result.byPosition.first;
    final closestName = predictions[closest.predictionId]!.name;
    final pace = result.byPace.isEmpty ? null : result.byPace.first;
    final rate = result.actualWeeklyRateKg;

    return Card(
      key: const Key('timeline-hero'),
      color: scheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CURRENT TIMELINE',
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tracking closest to',
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
            ),
            Text(
              '‘$closestName’',
              key: const Key('hero-closest-name'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _positionDetail(closest),
              key: const Key('hero-position-detail'),
              style: theme.textTheme.bodyMedium?.copyWith(color: onHero),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: onHero.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.speed, color: onHero, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: rate == null || pace == null
                        ? Text(
                            'Keep logging — measuring your pace needs '
                            'weigh-ins spanning at least a week.',
                            key: const Key('hero-pace-pending'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onHero,
                            ),
                          )
                        : _PaceInsight(
                            rate: rate,
                            pace: pace,
                            prediction: predictions[pace.predictionId]!,
                            unit: unit,
                            color: onHero,
                            muted: muted,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Trend weight ${Units.format(result.currentWeightKg, unit)}'
              ' · $logCount weigh-ins'
              '${DateUtils.isSameDay(result.asOf, now) ? '' : ' · as of ${shortDate.format(result.asOf)}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _positionDetail(PredictionEvaluation e) {
    final target = DateUtils.isSameDay(result.asOf, now)
        ? "today's projected weight"
        : 'its projected weight for ${shortDate.format(result.asOf)}';
    final delta = e.deltaFromActualKg;
    // Measured on displayed values so it agrees with the cards below.
    final actual = e.expectedWeightTodayKg + delta;
    final gap = delta >= 0
        ? Units.formatDifference(actual, e.expectedWeightTodayKg, unit)
        : Units.formatDifference(e.expectedWeightTodayKg, actual, unit);
    if (gap == Units.format(0, unit)) return 'Right on $target.';
    if (e.adherenceStatus == AdherenceStatus.offCourse) {
      return '$gap ${delta > 0 ? 'above' : 'below'} $target.';
    }
    return 'Within $gap of $target.';
  }
}

class _PaceInsight extends StatelessWidget {
  const _PaceInsight({
    required this.rate,
    required this.pace,
    required this.prediction,
    required this.unit,
    required this.color,
    required this.muted,
  });

  final double rate;
  final PredictionEvaluation pace;
  final PredictionSnapshot prediction;
  final WeightUnit unit;
  final Color color;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Round to 10 kcal: the estimate isn't more precise than that.
    final implied = (pace.impliedDailyCalories! / 10).round() * 10.0;
    final rateText =
        '${Units.format(rate, unit, decimals: 2, signed: true)}/wk';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          key: const Key('hero-pace'),
          TextSpan(
            children: [
              const TextSpan(text: 'Your 14-day pace ('),
              TextSpan(
                text: rateText,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ') implies '),
              TextSpan(
                text: '~${formatKcal(implied)}/day',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontFeatures: tabularFigures,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pace matches ‘${prediction.name}’ best '
          '(${Units.format(pace.expectedWeeklyRateKg, unit, decimals: 2, signed: true)}/wk'
          ', ${formatKcal(prediction.dailyCalories)} plan). '
          'Assumes ${prediction.activityLevel.longLabel}.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({
    required this.hasPredictions,
    required this.archivedCount,
    required this.logCount,
    required this.onCreatePrediction,
    required this.onLogWeight,
  });

  final bool hasPredictions;
  final int archivedCount;
  final int logCount;
  final VoidCallback onCreatePrediction;
  final VoidCallback onLogWeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needsLogs = logCount < minLogsForMatch;
    final message = switch ((hasPredictions, needsLogs)) {
      (false, _) when archivedCount > 0 =>
        'The Arena is empty — all $archivedCount of your predictions are '
            'archived. Restore one from the archive below, or lock in a '
            'new one.',
      (false, true) =>
        'Lock in a prediction and log a couple of weigh-ins to see which '
            'timeline you are actually on.',
      (false, false) =>
        'Lock in a prediction in the Simulator to see how reality compares.',
      _ =>
        'Log at least $minLogsForMatch weigh-ins to see which prediction '
            'you are tracking ($logCount so far).',
    };
    return Card(
      key: const Key('timeline-hero-empty'),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.timeline, color: scheme.onPrimaryContainer, size: 32),
            const SizedBox(height: 12),
            Text(
              'Find your timeline',
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!hasPredictions)
                  FilledButton.icon(
                    key: const Key('hero-create-prediction'),
                    onPressed: onCreatePrediction,
                    icon: const Icon(Icons.tune),
                    label: const Text('Create a prediction'),
                  ),
                // Logging is the primary action once a prediction exists.
                if (needsLogs && hasPredictions)
                  FilledButton.icon(
                    key: const Key('hero-log-weight'),
                    onPressed: onLogWeight,
                    icon: const Icon(Icons.monitor_weight_outlined),
                    label: const Text('Log weight'),
                  )
                else if (needsLogs)
                  OutlinedButton.icon(
                    key: const Key('hero-log-weight'),
                    onPressed: onLogWeight,
                    icon: const Icon(Icons.monitor_weight_outlined),
                    label: const Text('Log weight'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
