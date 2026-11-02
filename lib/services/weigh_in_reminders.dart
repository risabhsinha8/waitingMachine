import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../utils/units.dart';
import 'projection_milestones.dart';

/// One notification asking the user to weigh in on a day a prediction or
/// checkpoint falls due. Days with several due dates share one reminder.
@immutable
class WeighInReminder {
  const WeighInReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  /// Stable per day (yyyymmdd), so rescheduling replaces rather than stacks.
  final int id;

  /// Local time the reminder fires.
  final DateTime when;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is WeighInReminder &&
      other.id == id &&
      other.when == when &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, when, title, body);

  @override
  String toString() => 'WeighInReminder($when, $title)';
}

/// Reminders for the days the user's dates come due: each checkpoint, and
/// each day an Arena prediction said they'd reach its target or cross a
/// round number (see [findMilestones]).
///
/// Each fires at [hour] local time. Days already past, or today once
/// [hour] has gone by or a weigh-in is logged, are skipped. Only the
/// nearest [limit] days are kept (iOS holds at most 64 pending).
List<WeighInReminder> planWeighInReminders({
  required List<PredictionSnapshot> activePredictions,
  required List<Checkpoint> checkpoints,
  required List<WeightLog> weightLogs,
  required WeightUnit unit,
  required DateTime now,
  int hour = 9,
  int limit = 40,
}) {
  final today = _day(now);
  final loggedToday = weightLogs.any((l) => _day(l.date) == today);
  final byDay = <DateTime, List<({String title, String line})>>{};

  void add(DateTime date, String title, String line) {
    final day = _day(date);
    if (day.isBefore(today)) return;
    if (day == today && (loggedToday || !now.isBefore(_at(day, hour)))) {
      return;
    }
    (byDay[day] ??= []).add((title: title, line: line));
  }

  for (final c in checkpoints) {
    add(c.date, '${c.label} is today', 'Today is ${c.label}.');
  }

  for (final p in activePredictions) {
    final milestones = findMilestones(
      p.points,
      unit: unit,
      targetWeightKg: p.targetWeightKg,
    );
    for (var i = 0; i < milestones.length; i++) {
      final m = milestones[i];
      if (m == null) continue;
      final weight = Units.format(
        m.weightKg,
        unit,
        decimals: m.kind == MilestoneKind.target ? 1 : 0,
      );
      final line = switch (m.kind) {
        MilestoneKind.target => '${p.name} said you’d reach $weight today.',
        MilestoneKind.mark =>
          '${p.name} said you’d be ${m.losing ? 'under' : 'over'} '
              '$weight by today.',
      };
      add(p.points[i].date, 'Weigh-in day: ${p.name}', line);
    }
  }

  final days = byDay.keys.toList()..sort();
  return [
    for (final day in days.take(limit)) _reminder(day, hour, byDay[day]!),
  ];
}

WeighInReminder _reminder(
  DateTime day,
  int hour,
  List<({String title, String line})> items,
) {
  const cta = 'Weigh in to see who called it.';
  return WeighInReminder(
    id: day.year * 10000 + day.month * 100 + day.day,
    when: _at(day, hour),
    title: items.length == 1 ? items.single.title : 'Time to weigh in',
    body: [for (final i in items) i.line, cta].join('\n'),
  );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _at(DateTime day, int hour) =>
    DateTime(day.year, day.month, day.day, hour);
