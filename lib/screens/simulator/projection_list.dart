import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/projection_milestones.dart';
import '../../state/simulator_controller.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import '../../widgets/layout.dart';
import 'projection_chart.dart';

class ProjectionHeader extends StatelessWidget {
  const ProjectionHeader({super.key, required this.controller});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '${c.weeks}-week projection',
          trailing: const Caption('Burn updates as you lose'),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
            child: ProjectionChart(
              key: const Key('projection-chart'),
              points: c.points,
              milestones: c.milestones,
              unit: c.unit,
              targetWeightKg: c.targetWeightKg,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _ColumnLabels(),
      ],
    );
  }
}

/// Column captions above the weekly rows.
class _ColumnLabels extends StatelessWidget {
  const _ColumnLabels();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          SizedBox(width: _weekColumnWidth, child: Eyebrow('Week')),
          Expanded(child: Eyebrow('Projected')),
          Eyebrow('Change · Burn'),
        ],
      ),
    );
  }
}

const double _weekColumnWidth = 52;

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
      null => (Colors.transparent, scheme.onSurface),
    };
    final muted = milestone == null
        ? scheme.onSurfaceVariant
        : foreground.withValues(alpha: 0.75);

    return Container(
      margin: EdgeInsets.symmetric(vertical: milestone == null ? 0 : 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: milestone == null
            ? Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: _weekColumnWidth,
                child: Text(
                  isStart ? 'Now' : '${point.weekNumber}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isStart ? foreground : muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Units.format(point.projectedWeightKg, unit),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    Text(
                      projectionDate.format(point.date),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
                    formatKcal(point.dynamicTdee),
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
              padding: const EdgeInsets.only(top: 8, left: _weekColumnWidth),
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
                        fontWeight: FontWeight.w700,
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
