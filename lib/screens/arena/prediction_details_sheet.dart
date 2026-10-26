import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/losertown_math.dart';
import '../../services/prediction_comparison.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_theme.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import '../../widgets/drift_badge.dart';

/// Week-by-week table of a prediction against the user's logged weights.
Future<void> showPredictionDetailsSheet(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) =>
            _DetailsBody(id: id, scrollController: scrollController),
      ),
    );

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.id, required this.scrollController});

  final String id;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final p = app.predictionById(id);
    if (p == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final unit = app.unit;
    final now = app.now();
    final evaluation = app.evaluationFor(id);
    final weeks = compareWeeks(p, app.weightLogs);
    final logged = weeks.where((w) => w.hasLog).toList();
    final elapsed = weeks.where((w) => !w.point.date.isAfter(now)).length;
    final avgDrift = logged.isEmpty
        ? null
        : logged.map((w) => w.deltaKg!).reduce((a, b) => a + b) / logged.length;

    return CustomScrollView(
      key: const Key('details-sheet'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  rulesLabel(p, unit),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Started ${projectionDate.format(p.createdAt)} at '
                  '${Units.format(p.startWeightKg, unit)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (p.archivedAt case final archivedAt?)
                  Text(
                    'Archived ${projectionDate.format(archivedAt)} · '
                    'not competing in the Arena',
                    key: const Key('details-archived'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (evaluation != null)
                      DriftBadge(status: evaluation.adherenceStatus),
                    Text(
                      '${logged.length} of $elapsed weeks logged'
                      '${avgDrift == null ? '' : ' · avg drift ${Units.format(avgDrift, unit, signed: true)}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        PinnedHeaderSliver(
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLow,
            child: const _TableRow.header(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList.builder(
            itemCount: weeks.length,
            itemBuilder: (context, i) => _WeekRow(
              key: ValueKey('details-week-$i'),
              week: weeks[i],
              unit: unit,
              isCurrentWeek: _isCurrentWeek(weeks[i].point.date, now),
              isFuture: weeks[i].point.date.isAfter(now),
            ),
          ),
        ),
      ],
    );
  }

  static bool _isCurrentWeek(DateTime weekStart, DateTime now) =>
      !weekStart.isAfter(now) &&
      now.isBefore(weekStart.add(const Duration(days: 7)));
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    super.key,
    required this.week,
    required this.unit,
    required this.isCurrentWeek,
    required this.isFuture,
  });

  final WeekComparison week;
  final WeightUnit unit;
  final bool isCurrentWeek;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final point = week.point;
    final delta = week.deltaKg;
    final deltaColor = delta == null
        ? null
        : switch (LosertownMath.classifyAdherence(delta, unit: unit)) {
            AdherenceStatus.onTrack => status.onGood,
            AdherenceStatus.drifting => status.onWarn,
            AdherenceStatus.offCourse => status.onBad,
          };
    final loggedOnOtherDay =
        week.loggedDate != null &&
        !DateUtils.isSameDay(week.loggedDate, point.date);

    return Container(
      color: isCurrentWeek ? scheme.primaryContainer : null,
      child: Opacity(
        opacity: isFuture ? 0.55 : 1,
        child: _TableRow(
          week: point.weekNumber == 0 ? 'Start' : '${point.weekNumber}',
          date: shortDate.format(point.date),
          projected: Units.format(point.projectedWeightKg, unit),
          logged: week.loggedWeightKg == null
              ? '—'
              : Units.format(week.loggedWeightKg!, unit),
          loggedNote: loggedOnOtherDay
              ? 'on ${shortDate.format(week.loggedDate!)}'
              : null,
          delta: delta == null
              ? '—'
              : Units.formatDifference(
                  week.loggedWeightKg!,
                  week.loggedWeightKg! - delta,
                  unit,
                  signed: true,
                ),
          deltaColor: deltaColor,
          emphasize: isCurrentWeek,
        ),
      ),
    );
  }
}

/// Fixed column layout shared by the header and the rows.
class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.week,
    required this.date,
    required this.projected,
    required this.logged,
    required this.delta,
    this.loggedNote,
    this.deltaColor,
    this.emphasize = false,
  }) : isHeader = false;

  const _TableRow.header()
    : week = 'Wk',
      date = 'Date',
      projected = 'Projected',
      logged = 'Logged',
      delta = 'Δ',
      loggedNote = null,
      deltaColor = null,
      emphasize = false,
      isHeader = true;

  final String week;
  final String date;
  final String projected;
  final String logged;
  final String delta;
  final String? loggedNote;
  final Color? deltaColor;
  final bool emphasize;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final base = isHeader
        ? theme.textTheme.labelMedium?.copyWith(color: muted)
        : theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: tabularFigures,
            fontWeight: emphasize ? FontWeight.w600 : null,
          );

    Widget cell(String text, {int flex = 3, Color? color, String? note}) =>
        Expanded(
          flex: flex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(text, style: base?.copyWith(color: color)),
              if (note != null)
                Text(
                  note,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 44, child: Text(week, style: base)),
          Expanded(flex: 3, child: Text(date, style: base)),
          cell(projected),
          cell(logged, note: loggedNote),
          cell(delta, color: deltaColor),
        ],
      ),
    );
  }
}
