import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/projection_milestones.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';

/// The whole projection at a glance: the weight curve, the target (if any)
/// and round-number milestones, with a tap-to-inspect crosshair.
class ProjectionChart extends StatelessWidget {
  const ProjectionChart({
    super.key,
    required this.points,
    required this.milestones,
    required this.unit,
    this.targetWeightKg,
  });

  final List<WeeklyProjectionPoint> points;

  /// Parallel to [points].
  final List<ProjectionMilestone?> milestones;
  final WeightUnit unit;
  final double? targetWeightKg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: muted,
      fontFeatures: tabularFigures,
    );
    double y(double kg) => Units.fromKg(kg, unit);

    final values = [
      for (final p in points) y(p.projectedWeightKg),
      if (targetWeightKg != null) y(targetWeightKg!),
    ];
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final interval = _niceInterval(hi - lo);
    final minY = (lo / interval).floor() * interval - interval * 0.25;
    final maxY = (hi / interval).ceil() * interval + interval * 0.25;
    final maxX = (points.length - 1).toDouble();
    final xInterval = maxX > 60 ? 26.0 : 13.0;

    final spots = [
      for (final p in points)
        FlSpot(p.weekNumber.toDouble(), y(p.projectedWeightKg)),
    ];
    final line = scheme.primary;

    return Semantics(
      label:
          'Projection chart from ${Units.format(points.first.projectedWeightKg, unit)} '
          'to ${Units.format(points.last.projectedWeightKg, unit)} '
          'over ${points.length - 1} weeks',
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            clipData: const FlClipData.all(),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: line,
                barWidth: 3,
                isCurved: true,
                preventCurveOverShooting: true,
                isStrokeCapRound: true,
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      line.withValues(alpha: 0.28),
                      line.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                dotData: FlDotData(
                  checkToShowDot: (spot, _) {
                    final i = spot.x.round();
                    return i == 0 || milestones[i] != null;
                  },
                  getDotPainter: (spot, _, _, _) {
                    final m = milestones[spot.x.round()];
                    final isTarget = m?.kind == MilestoneKind.target;
                    return FlDotCirclePainter(
                      radius: isTarget ? 5.5 : 4,
                      color: isTarget ? scheme.tertiary : line,
                      strokeWidth: 2,
                      strokeColor: scheme.surfaceContainerLow,
                    );
                  },
                ),
              ),
            ],
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (targetWeightKg != null)
                  HorizontalLine(
                    y: y(targetWeightKg!),
                    color: scheme.tertiary,
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: labelStyle?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                      labelResolver: (_) =>
                          'Target ${Units.format(targetWeightKg!, unit)}',
                    ),
                  ),
              ],
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: interval,
                  getTitlesWidget: (value, meta) => value % interval != 0
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(
                            value.toStringAsFixed(interval % 1 == 0 ? 0 : 1),
                            style: labelStyle,
                          ),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: xInterval,
                  getTitlesWidget: (value, meta) => value % xInterval != 0
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            value == 0 ? 'Now' : 'Wk ${value.round()}',
                            style: labelStyle,
                          ),
                        ),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchSpotThreshold: 24,
              getTouchedSpotIndicator: (bar, indexes) => [
                for (final _ in indexes)
                  TouchedSpotIndicatorData(
                    FlLine(color: muted, strokeWidth: 1, dashArray: [3, 3]),
                    FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 5,
                        color: line,
                        strokeWidth: 2,
                        strokeColor: scheme.surface,
                      ),
                    ),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                tooltipBorderRadius: BorderRadius.circular(10),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (final s in spots) _tooltip(context, points[s.x.round()]),
                ],
              ),
            ),
          ),
          duration: const Duration(milliseconds: 250),
        ),
      ),
    );
  }

  LineTooltipItem _tooltip(BuildContext context, WeeklyProjectionPoint p) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onInverseSurface;
    final base = theme.textTheme.bodySmall!.copyWith(
      color: ink,
      fontFeatures: tabularFigures,
    );
    return LineTooltipItem(
      Units.format(p.projectedWeightKg, unit),
      base.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      children: [
        TextSpan(
          text:
              '\n${p.weekNumber == 0 ? 'Now' : 'Week ${p.weekNumber}'}'
              ' · ${shortDate.format(p.date)}',
          style: base.copyWith(color: ink.withValues(alpha: 0.75)),
        ),
      ],
    );
  }

  /// A round grid step giving roughly four lines over [range].
  static double _niceInterval(double range) {
    if (range <= 0) return 1;
    final raw = range / 4;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    for (final step in [1, 2, 2.5, 5, 10]) {
      if (raw <= step * magnitude) return step * magnitude.toDouble();
    }
    return 10.0 * magnitude;
  }
}
