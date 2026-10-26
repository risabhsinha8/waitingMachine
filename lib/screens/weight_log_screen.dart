import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';
import '../ui/haptics.dart';
import '../utils/units.dart';
import '../widgets/quick_log.dart';
import '../widgets/weight_entry_form.dart';

/// Tab 3: log a weigh-in and review raw vs. trend history.
class WeightLogScreen extends StatelessWidget {
  const WeightLogScreen({super.key});

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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: logs.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
          return Padding(
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

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.smoothed, required this.unit});

  final List<SmoothedWeight> smoothed;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (smoothed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 32, 4, 0),
        child: Text(
          'No weigh-ins yet. Log one above — your 7-day trend appears '
          'after a few days.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
      );
    }
    final weekChange = _weekChange();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('History', style: theme.textTheme.titleMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Trend ${Units.format(smoothed.last.smoothedWeightKg, unit)}'
              '${weekChange == null ? '' : ' · ${Units.format(weekChange, unit, signed: true)} in 7 days'}',
              key: const Key('trend-summary'),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.delete_outline, color: colors.onBad),
    );
  }
}
