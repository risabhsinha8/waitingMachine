import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import 'prediction_card.dart';

/// Tappable "Archive (N)" header that expands the archived list.
class ArchiveHeader extends StatelessWidget {
  const ArchiveHeader({
    super.key,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: InkWell(
        key: const Key('archive-toggle'),
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 20, color: muted),
              const SizedBox(width: 10),
              Text('Archive ($count)', style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  expanded ? '' : 'Kept with full history',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact row for an archived prediction: rules, when it was archived,
/// how it would compare today, and a one-tap Restore.
class ArchivedPredictionTile extends StatelessWidget {
  const ArchivedPredictionTile({
    super.key,
    required this.prediction,
    required this.evaluation,
    required this.unit,
    required this.onTap,
    required this.onRestore,
    required this.onAction,
  });

  final PredictionSnapshot prediction;
  final PredictionEvaluation? evaluation;
  final WeightUnit unit;
  final VoidCallback onTap;
  final VoidCallback onRestore;

  /// Open in Simulator, Clone or Delete.
  final ValueChanged<PredictionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final p = prediction;
    final e = evaluation;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: tabularFigures,
    );

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      '${formatKcal(p.dailyCalories)} · '
                      '${p.activityLevel.label} · '
                      'archived ${shortDate.format(p.archivedAt!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                    if (e != null)
                      Text(
                        'Today: ${e.adherenceStatus.label} · '
                        '${Units.formatDifference(e.expectedWeightTodayKg + e.deltaFromActualKg, e.expectedWeightTodayKg, unit, signed: true)}'
                        ' vs projected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                key: ValueKey('restore-${p.id}'),
                onPressed: onRestore,
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('Restore'),
              ),
              PopupMenuButton<PredictionAction>(
                key: const Key('archived-menu'),
                tooltip: 'Archived prediction actions',
                onSelected: onAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: PredictionAction.openInSimulator,
                    child: ListTile(
                      leading: Icon(Icons.tune),
                      title: Text('Open in Simulator'),
                    ),
                  ),
                  PopupMenuItem(
                    value: PredictionAction.clone,
                    child: ListTile(
                      leading: Icon(Icons.copy_outlined),
                      title: Text('Clone'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: PredictionAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
