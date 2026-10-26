import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/checkpoint_forecast.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import '../../widgets/drift_badge.dart';
import '../../widgets/series_key.dart';

enum PredictionAction { reanchor, openInSimulator, clone, archive, delete }

/// A saved prediction compared against the user's current trend.
class PredictionCard extends StatelessWidget {
  const PredictionCard({
    super.key,
    required this.prediction,
    required this.evaluation,
    required this.asOf,
    required this.now,
    required this.unit,
    required this.canReanchor,
    required this.onTap,
    required this.onAction,
    this.checkpoints = const [],
  });

  final PredictionSnapshot prediction;

  /// Null when there are no weigh-ins to compare against.
  final PredictionEvaluation? evaluation;

  /// Day the comparison is for (the latest weigh-in).
  final DateTime? asOf;
  final DateTime now;
  final WeightUnit unit;
  final bool canReanchor;
  final VoidCallback onTap;
  final ValueChanged<PredictionAction> onAction;

  /// This prediction's forecast for each pinned goal date.
  final List<CheckpointForecast> checkpoints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = prediction;
    final e = evaluation;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Keys the card to its line on the chart.
                            if (p.colorSlot case final slot?) ...[
                              SeriesKey(
                                key: const Key('card-series-key'),
                                color: SeriesColors.of(context, slot),
                                dash: seriesDash(slot),
                                width: 3,
                                length: 18,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Created ${projectionDate.format(p.createdAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (e != null) DriftBadge(status: e.adherenceStatus),
                  _ActionsMenu(canReanchor: canReanchor, onAction: onAction),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _RulesBadge(label: rulesLabel(p, unit)),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: e == null
                    ? Text(
                        'Log a weigh-in to compare this prediction with '
                        'reality.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : _Comparison(
                        evaluation: e,
                        asOf: asOf!,
                        now: now,
                        unit: unit,
                      ),
              ),
              if (checkpoints.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _CheckpointRow(
                    forecasts: checkpoints,
                    unit: unit,
                    fromToday: e != null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Beach Trip · Dec 15 → 81.9 kg" for each pinned goal date.
class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.forecasts,
    required this.unit,
    required this.fromToday,
  });

  final List<CheckpointForecast> forecasts;
  final WeightUnit unit;

  /// Whether upcoming dates are projected from today's trend (vs. the
  /// prediction's original timeline, when there are no weigh-ins).
  final bool fromToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Column(
      key: const Key('checkpoint-row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fromToday
              ? 'Checkpoints · if you follow this from today'
              : 'Checkpoints · on this timeline',
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, f) in forecasts.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.checkpoint.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        f.isPast
                            ? '${shortDate.format(f.checkpoint.date)} · past'
                            : shortDate.format(f.checkpoint.date),
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        f.weightKg == null
                            ? 'Beyond plan'
                            : Units.format(f.weightKg!, unit),
                        maxLines: 1,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                          color: f.isPast || f.weightKg == null ? muted : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.canReanchor, required this.onAction});

  final bool canReanchor;
  final ValueChanged<PredictionAction> onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PredictionAction>(
      key: const Key('prediction-menu'),
      tooltip: 'Prediction actions',
      onSelected: onAction,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: PredictionAction.reanchor,
          enabled: canReanchor,
          child: const ListTile(
            leading: Icon(Icons.restart_alt),
            title: Text('Re-anchor to Today'),
          ),
        ),
        const PopupMenuItem(
          value: PredictionAction.openInSimulator,
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Open in Simulator'),
          ),
        ),
        const PopupMenuItem(
          value: PredictionAction.clone,
          child: ListTile(
            leading: Icon(Icons.copy_outlined),
            title: Text('Clone'),
          ),
        ),
        const PopupMenuItem(
          value: PredictionAction.archive,
          child: ListTile(
            leading: Icon(Icons.archive_outlined),
            title: Text('Archive'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: PredictionAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete'),
          ),
        ),
      ],
    );
  }
}

class _RulesBadge extends StatelessWidget {
  const _RulesBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 15,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Projected today" vs "Actual trend", side by side.
class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.evaluation,
    required this.asOf,
    required this.now,
    required this.unit,
  });

  final PredictionEvaluation evaluation;
  final DateTime asOf;
  final DateTime now;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = evaluation;
    final actualKg = e.expectedWeightTodayKg + e.deltaFromActualKg;
    final projectedLabel = DateUtils.isSameDay(asOf, now)
        ? 'Projected today'
        : 'Projected ${shortDate.format(asOf)}';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                label: projectedLabel,
                value: Units.format(e.expectedWeightTodayKg, unit),
              ),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: _Metric(
                label: 'Actual trend',
                value: Units.format(actualKg, unit),
                detail:
                    '${Units.formatDifference(actualKg, e.expectedWeightTodayKg, unit, signed: true)} '
                    'vs projected',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: tabularFigures,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontFeatures: tabularFigures,
              ),
            ),
        ],
      ),
    );
  }
}
