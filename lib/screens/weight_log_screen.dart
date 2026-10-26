import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';
import '../ui/haptics.dart';
import '../ui/labels.dart';
import '../utils/units.dart';
import '../widgets/layout.dart';
import '../widgets/quick_log.dart';
import '../widgets/weight_entry_form.dart';

/// Tab 3: log a weigh-in and review raw vs. trend history.
class WeightLogScreen extends StatelessWidget {
  const WeightLogScreen({super.key});

  static final DateFormat _month = DateFormat('MMMM yyyy');

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final unit = app.unit;
    final smoothed = app.smoothedWeights;
    final trendByDay = {
      for (final (i, s) in smoothed.indexed) DateUtils.dateOnly(s.date): i,
    };
    final logs = app.weightLogs.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weight Log'),
        actions: const [QuickLogButton()],
      ),
      body: ListView.builder(
        key: const Key('weight-log-list'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: contentPadding(context),
        itemCount: logs.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: WeightEntryForm(
                  onSaved: (log) => showLoggedSnackBar(context, log),
                ),
              ),
            );
          }
          if (index == 1) {
            return _HistoryHeader(smoothed: smoothed, unit: unit);
          }
          final log = logs[index - 2];
          final i = trendByDay[DateUtils.dateOnly(log.date)]!;
          final previous = index > 2 ? logs[index - 3] : null;
          final newMonth =
              previous == null ||
              previous.date.month != log.date.month ||
              previous.date.year != log.date.year;
          final row = Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Dismissible(
              key: ValueKey('dismiss-log-${log.id}'),
              direction: DismissDirection.endToStart,
              background: const _DeleteBackground(),
              onDismissed: (_) => _delete(context, log),
              child: _LogRow(
                key: ValueKey('log-row-${log.id}'),
                log: log,
                trend: smoothed[i],
                previousTrend: i > 0 ? smoothed[i - 1] : null,
                unit: unit,
              ),
            ),
          );
          if (!newMonth) return row;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  4,
                  previous == null ? 0 : 14,
                  4,
                  8,
                ),
                child: Eyebrow(_month.format(log.date)),
              ),
              row,
            ],
          );
        },
      ),
    );
  }

  static Future<void> _delete(BuildContext context, WeightLog log) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    await app.deleteWeightLog(log.id);
    Haptics.deleted();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${Units.format(log.weightKg, app.unit)}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => app.restoreWeightLog(log),
          ),
        ),
      );
  }
}

/// Trend weight, recent change and a sparkline above the history list.
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.smoothed, required this.unit});

  /// How much history the sparkline shows.
  static const int _sparkDays = 60;

  final List<SmoothedWeight> smoothed;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (smoothed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
        child: Column(
          children: [
            Icon(Icons.show_chart, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No weigh-ins yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Log one above. Your 7-day trend smooths out daily water '
              'swings and appears after a few days.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      );
    }
    final latest = smoothed.last;
    final weekChange = _weekChange();
    final totalChange = smoothed.length > 1
        ? latest.smoothedWeightKg - smoothed.first.smoothedWeightKg
        : null;
    final recent = smoothed.length > _sparkDays
        ? smoothed.sublist(smoothed.length - _sparkDays)
        : smoothed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Trend weight'),
                        const SizedBox(height: 2),
                        Text(
                          Units.format(latest.smoothedWeightKg, unit),
                          key: const Key('trend-summary'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: recent.length > 1
                          ? SizedBox(
                              height: 52,
                              child: _Sparkline(points: recent, unit: unit),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (weekChange != null)
                      _ChangeChip(
                        label: '7 days',
                        changeKg: weekChange,
                        unit: unit,
                      ),
                    if (totalChange != null)
                      _ChangeChip(
                        label: 'since ${shortDate.format(smoothed.first.date)}',
                        changeKg: totalChange,
                        unit: unit,
                      ),
                    Text(
                      '${smoothed.length} '
                      '${smoothed.length == 1 ? 'day' : 'days'} logged',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'History'),
      ],
    );
  }

  /// Trend change versus the latest trend at least 7 days earlier.
  double? _weekChange() {
    final latest = smoothed.last;
    final cutoff = latest.date.subtract(const Duration(days: 7));
    for (final s in smoothed.reversed) {
      if (!s.date.isAfter(cutoff)) {
        return latest.smoothedWeightKg - s.smoothedWeightKg;
      }
    }
    return null;
  }
}

/// "−0.4 kg · 7 days", green going down and amber going up.
class _ChangeChip extends StatelessWidget {
  const _ChangeChip({
    required this.label,
    required this.changeKg,
    required this.unit,
  });

  final String label;
  final double changeKg;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final text = Units.format(changeKg, unit, signed: true);
    final flat = text == Units.format(0, unit);
    final (bg, fg, icon) = flat
        ? (
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.onSurfaceVariant,
            Icons.trending_flat,
          )
        : changeKg < 0
        ? (status.good, status.onGood, Icons.trending_down)
        : (status.warn, status.onWarn, Icons.trending_up);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: text,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  TextSpan(
                    text: ' · $label',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// The recent trend as a small filled line.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.points, required this.unit});

  final List<SmoothedWeight> points;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateUtils.dateOnly(points.first.date);
    final spots = [
      for (final p in points)
        FlSpot(
          DateUtils.dateOnly(p.date).difference(first).inDays.toDouble(),
          Units.fromKg(p.smoothedWeightKg, unit),
        ),
    ];
    final ys = spots.map((s) => s.y);
    final lo = ys.reduce(math.min);
    final hi = ys.reduce(math.max);
    final pad = math.max((hi - lo) * 0.15, 0.2);
    final color = scheme.primary;
    return ExcludeSemantics(
      child: LineChart(
        LineChartData(
          minY: lo - pad,
          maxY: hi + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: color,
              barWidth: 2.5,
              isCurved: true,
              preventCurveOverShooting: true,
              isStrokeCapRound: true,
              dotData: FlDotData(
                checkToShowDot: (spot, _) => spot == spots.last,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: scheme.surfaceContainerLow,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    super.key,
    required this.log,
    required this.trend,
    required this.previousTrend,
    required this.unit,
  });

  static final DateFormat _weekday = DateFormat('EEE');
  static final DateFormat _monthDay = DateFormat('MMM d');

  final WeightLog log;
  final SmoothedWeight trend;
  final SmoothedWeight? previousTrend;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final now = trend.smoothedWeightKg;
    final before = previousTrend?.smoothedWeightKg;
    final falling = before != null && now < before;
    // Measured on the displayed values, so the arrow always agrees with the
    // two trend numbers on screen; hidden when they read the same.
    final change = before == null
        ? null
        : Units.formatDifference(
            falling ? before : now,
            falling ? now : before,
            unit,
          );
    final showChange = change != null && change != Units.format(0, unit);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _weekday.format(log.date).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                Text(
                  _monthDay.format(log.date),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: _Value(
              label: 'Scale',
              value: Units.format(log.weightKg, unit),
              emphasize: true,
            ),
          ),
          Expanded(
            child: _Value(
              label: '7-day trend',
              value: Units.format(trend.smoothedWeightKg, unit),
              trailing: !showChange
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          falling ? Icons.south : Icons.north,
                          size: 12,
                          color: muted,
                        ),
                        Text(
                          change,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        // Wraps the change badge under the value when the column is narrow.
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              value,
              style:
                  (emphasize
                          ? theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontFeatures: tabularFigures),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colors = StatusColors.of(context);
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: colors.bad,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.delete_outline, color: colors.onBad),
    );
  }
}
