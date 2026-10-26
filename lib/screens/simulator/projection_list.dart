import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/projection_milestones.dart';
import '../../state/simulator_controller.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';

class ProjectionHeader extends StatelessWidget {
  const ProjectionHeader({super.key, required this.controller});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              '${controller.weeks}-week projection',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            'TDEE updates as you lose',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One week of the projection.
class ProjectionRow extends StatelessWidget {
  const ProjectionRow({
    super.key,
    required this.point,
    required this.milestone,
    required this.unit,
  });

  final WeeklyProjectionPoint point;
  final ProjectionMilestone? milestone;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isStart = point.weekNumber == 0;
    final (background, foreground) = switch (milestone?.kind) {
      MilestoneKind.target => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      MilestoneKind.mark => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      null => (scheme.surfaceContainerLow, scheme.onSurface),
    };
    final muted = milestone == null
        ? scheme.onSurfaceVariant
        : foreground.withValues(alpha: 0.75);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WEEK',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                    Text(
                      isStart ? 'Now' : '${point.weekNumber}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      projectionDate.format(point.date),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    Text(
                      Units.format(point.projectedWeightKg, unit),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  isStart
                      ? const _Badge.neutral(label: 'Start')
                      : _ChangeBadge(
                          changeKg: point.weeklyChangeKg,
                          unit: unit,
                        ),
                  const SizedBox(height: 4),
                  Text(
                    'TDEE ${formatKcal(point.dynamicTdee)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (milestone case final m?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    m.kind == MilestoneKind.target
                        ? Icons.flag
                        : Icons.military_tech,
                    size: 18,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _milestoneLabel(m),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _milestoneLabel(ProjectionMilestone m) => switch (m.kind) {
    MilestoneKind.target =>
      'Target reached · ${Units.format(m.weightKg, unit)}',
    MilestoneKind.mark =>
      '${m.losing ? 'Below' : 'Above'} '
          '${Units.format(m.weightKg, unit, decimals: 0)}',
  };
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.changeKg, required this.unit});

  final double changeKg;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (Units.fromKg(changeKg, unit).abs() < 0.005) {
      return const _Badge.neutral(label: 'Hold');
    }
    final losing = changeKg < 0;
    return _Badge(
      label: Units.format(changeKg, unit, decimals: 2, signed: true),
      icon: losing ? Icons.south : Icons.north,
      background: losing ? scheme.primaryContainer : scheme.tertiaryContainer,
      foreground: losing
          ? scheme.onPrimaryContainer
          : scheme.onTertiaryContainer,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.icon,
    this.background,
    this.foreground,
  });

  const _Badge.neutral({required this.label})
    : icon = null,
      background = null,
      foreground = null;

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = foreground ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
