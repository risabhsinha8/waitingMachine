import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import '../../widgets/series_key.dart';
import 'timeline_chart_data.dart';

/// Saved predictions (dashed) against the actual 7-day trend (solid), with a
/// time-window selector, a crosshair tooltip, and per-prediction filters.
class TimelineChart extends StatefulWidget {
  const TimelineChart({
    super.key,
    required this.predictions,
    required this.smoothed,
    required this.unit,
    required this.now,
  });

  /// The Arena's predictions; each draws in its own [colorSlot].
  final List<PredictionSnapshot> predictions;
  final List<SmoothedWeight> smoothed;
  final WeightUnit unit;
  final DateTime now;

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart>
    with AutomaticKeepAliveClientMixin {
  late ChartWindow _window = ChartWindow.fitting(
    [
      if (widget.smoothed.isNotEmpty) widget.smoothed.first.date,
      for (final p in widget.predictions) p.createdAt,
    ].fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a),
    widget.now,
  );
  final Set<String> _hidden = {};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final data = TimelineChartData.build(
      window: _window,
      now: widget.now,
      predictions: widget.predictions,
      hiddenIds: _hidden,
      smoothed: widget.smoothed,
      unit: widget.unit,
    );

    return Card(
      key: const Key('timeline-chart'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Wraps the selector under the title on narrow screens.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('Timelines', style: theme.textTheme.titleMedium),
                SegmentedButton<ChartWindow>(
                  key: const Key('chart-window'),
                  segments: [
                    for (final w in ChartWindow.values)
                      ButtonSegment(value: w, label: Text(w.label)),
                  ],
                  selected: {_window},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (s) => setState(() => _window = s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: data.isEmpty
                  ? _EmptyChart(hasPredictions: widget.predictions.isNotEmpty)
                  : LineChart(_chartData(context, data)),
            ),
            const SizedBox(height: 12),
            _Legend(hasRaw: data.rawSpots.isNotEmpty),
            if (widget.predictions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (i, p) in widget.predictions.indexed)
                    FilterChip(
                      key: ValueKey('chart-filter-${p.id}'),
                      avatar: SeriesKey(
                        color: SeriesColors.of(context, p.colorSlot ?? i),
                        dash: seriesDash(p.colorSlot ?? i),
                      ),
                      showCheckmark: false,
                      label: Text(p.name),
                      selected: !_hidden.contains(p.id),
                      onSelected: (on) => setState(
                        () => on ? _hidden.remove(p.id) : _hidden.add(p.id),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  LineChartData _chartData(BuildContext context, TimelineChartData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: muted,
      fontFeatures: tabularFigures,
    );

    // An invisible series with a spot on every day, so the crosshair snaps
    // to whole days and the tooltip can read every timeline on that day.
    final cursor = LineChartBarData(
      spots: [for (var x = 0.0; x <= data.maxX; x++) FlSpot(x, data.minY)],
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );
    bool isCursor(LineChartBarData bar) =>
        bar.barWidth == 0 && !bar.dotData.show;

    final trendDotRadius = data.trendSpots.length <= 45 ? 3.5 : 2.5;

    return LineChartData(
      minX: 0,
      maxX: data.maxX,
      minY: data.minY,
      maxY: data.maxY,
      clipData: const FlClipData.all(),
      lineBarsData: [
        cursor,
        for (final s in data.predictionSeries)
          LineChartBarData(
            spots: s.spots,
            color: SeriesColors.of(context, s.slot),
            barWidth: 2,
            dashArray: seriesDash(s.slot),
            dotData: const FlDotData(show: false),
          ),
        // Raw scale weight: faint dots only.
        if (data.rawSpots.isNotEmpty)
          LineChartBarData(
            spots: data.rawSpots,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2.5,
                color: muted.withValues(alpha: 0.35),
                strokeWidth: 0,
              ),
            ),
          ),
        // Actual trend: bold, solid, on top.
        if (data.trendSpots.isNotEmpty)
          LineChartBarData(
            spots: data.trendSpots,
            color: ink,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            isStrokeCapRound: true,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: trendDotRadius,
                color: ink,
                strokeWidth: 2,
                strokeColor: scheme.surfaceContainerLow,
              ),
            ),
          ),
      ],
      extraLinesData: ExtraLinesData(
        verticalLines: [
          VerticalLine(
            x: data.xOf(data.today),
            color: scheme.outline,
            strokeWidth: 1,
            dashArray: const [3, 3],
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: labelStyle,
              labelResolver: (_) => 'Today',
            ),
          ),
        ],
      ),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: data.yInterval,
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
            reservedSize: 40,
            interval: data.yInterval,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                value.toStringAsFixed(data.yInterval < 1 ? 1 : 0),
                style: labelStyle,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: data.xInterval,
            // fl_chart also labels the axis ends; skip those off-grid ones
            // so they can't collide with the regular labels.
            getTitlesWidget: (value, meta) => value % data.xInterval != 0
                ? const SizedBox.shrink()
                : SideTitleWidget(
                    meta: meta,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      shortDate.format(data.dateOf(value)),
                      style: labelStyle,
                    ),
                  ),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchSpotThreshold: 16,
        getTouchLineStart: (_, _) => data.minY,
        getTouchLineEnd: (_, _) => data.maxY,
        getTouchedSpotIndicator: (bar, indexes) => [
          for (final _ in indexes)
            isCursor(bar)
                ? TouchedSpotIndicatorData(
                    FlLine(color: muted, strokeWidth: 1),
                    const FlDotData(show: false),
                  )
                : null,
        ],
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => scheme.surfaceContainerHighest,
          tooltipBorder: BorderSide(color: scheme.outlineVariant),
          tooltipBorderRadius: BorderRadius.circular(10),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          maxContentWidth: 240,
          getTooltipItems: (spots) => [
            for (final spot in spots)
              isCursor(spot.bar)
                  ? _tooltip(context, data, data.dateOf(spot.x))
                  : null,
          ],
        ),
      ),
    );
  }

  /// Date, then actual trend and scale weight, then each prediction. Values
  /// lead and names follow; a short colored stroke keys each prediction.
  LineTooltipItem _tooltip(
    BuildContext context,
    TimelineChartData data,
    DateTime day,
  ) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final base = theme.textTheme.bodySmall!.copyWith(
      color: ink,
      fontFeatures: tabularFigures,
    );
    final strong = base.copyWith(fontWeight: FontWeight.w700);
    final quiet = base.copyWith(color: muted);
    String fmt(double kg) => Units.format(kg, data.unit);

    final trend = data.trendOn(day);
    final raw = data.rawOn(day);
    return LineTooltipItem(
      projectionDate.format(day),
      strong,
      textAlign: TextAlign.left,
      children: [
        TextSpan(text: '\n${trend == null ? '—' : fmt(trend)}', style: strong),
        TextSpan(text: '  actual trend', style: quiet),
        if (raw != null) ...[
          TextSpan(text: '\n${fmt(raw)}', style: base),
          TextSpan(text: '  scale', style: quiet),
        ],
        for (final r in data.projectionsOn(day)) ...[
          TextSpan(
            text: '\n━ ',
            style: base.copyWith(color: SeriesColors.of(context, r.slot)),
          ),
          TextSpan(text: fmt(r.weightKg), style: strong),
          TextSpan(text: '  ${r.prediction.name}', style: quiet),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.hasRaw});

  final bool hasRaw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    Widget item(Widget key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        key,
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: style)),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        item(
          SeriesKey(color: scheme.onSurface, width: 3, dot: true),
          'Actual trend',
        ),
        if (hasRaw)
          item(
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
            'Scale weight',
          ),
        item(
          SeriesKey(color: scheme.onSurfaceVariant, dash: const [4, 3]),
          'Prediction (tap below to hide)',
        ),
      ],
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.hasPredictions});

  final bool hasPredictions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        hasPredictions
            ? 'Nothing to plot in this window yet.'
            : 'Lock in a prediction or log weigh-ins to see your timelines.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
