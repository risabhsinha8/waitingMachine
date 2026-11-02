import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/reminder_notifications.dart';
import 'package:losertown/services/weigh_in_reminders.dart';
import 'package:losertown/state/app_state.dart';
import 'package:losertown/state/reminder_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loses 3 kg a week from 91 kg, reaching an 82 kg target in week 3.
PredictionSnapshot _prediction(DateTime start) => PredictionSnapshot(
  id: 'p1',
  name: 'Cut',
  createdAt: start,
  startWeightKg: 91,
  dailyCalories: 1800,
  activityLevel: ActivityLevel.lightlyActive,
  targetWeightKg: 82,
  points: [
    for (final (week, kg) in [(0, 91.0), (1, 88.0), (2, 85.0), (3, 82.0)])
      WeeklyProjectionPoint(
        weekNumber: week,
        date: DateTime(start.year, start.month, start.day + 7 * week),
        projectedWeightKg: kg,
        weeklyChangeKg: week == 0 ? 0 : -3,
        dynamicTdee: 2400,
      ),
  ],
);

class _FakeScheduler implements ReminderScheduler {
  final scheduled = <List<WeighInReminder>>[];
  var permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(List<WeighInReminder> reminders) async =>
      scheduled.add(reminders);

  @override
  ValueListenable<int> get taps => ValueNotifier(0);
}

void main() {
  final start = DateTime(2026, 1, 5);

  List<WeighInReminder> plan({
    required DateTime now,
    List<Checkpoint> checkpoints = const [],
    List<WeightLog> logs = const [],
  }) => planWeighInReminders(
    activePredictions: [_prediction(start)],
    checkpoints: checkpoints,
    weightLogs: logs,
    unit: WeightUnit.kg,
    now: now,
  );

  test('reminds on mark crossings and the target date at 9am', () {
    final reminders = plan(now: DateTime(2026, 1, 5, 12));
    expect(reminders.map((r) => r.when), [
      DateTime(2026, 1, 12, 9), // crosses 90
      DateTime(2026, 1, 19, 9), // crosses 85
      DateTime(2026, 1, 26, 9), // reaches 82 target
    ]);
    expect(reminders[1].id, 20260119);
    expect(reminders[1].title, 'Weigh-in day: Cut');
    expect(reminders[1].body, contains('under 85 kg by today'));
    expect(reminders.last.body, contains('reach 82.0 kg today'));
  });

  test('merges a checkpoint on the same day into one reminder', () {
    final reminders = plan(
      now: DateTime(2026, 1, 5, 12),
      checkpoints: [
        Checkpoint(id: 'c', label: 'Beach Trip', date: DateTime(2026, 1, 26)),
      ],
    );
    expect(reminders, hasLength(3));
    expect(reminders.last.title, 'Time to weigh in');
    expect(reminders.last.body, contains('Today is Beach Trip.'));
    expect(reminders.last.body, contains('reach 82.0 kg'));
  });

  test('skips today once its hour passes or a weigh-in is logged', () {
    final checkpoint = [
      Checkpoint(id: 'c', label: 'Party', date: DateTime(2026, 1, 19)),
    ];
    expect(
      plan(now: DateTime(2026, 1, 19, 8), checkpoints: checkpoint).first.when,
      DateTime(2026, 1, 19, 9),
    );
    expect(
      plan(now: DateTime(2026, 1, 19, 9), checkpoints: checkpoint).first.when,
      DateTime(2026, 1, 26, 9),
    );
    expect(
      plan(
        now: DateTime(2026, 1, 19, 7),
        checkpoints: checkpoint,
        logs: [
          WeightLog(id: 'w', date: DateTime(2026, 1, 19, 6), weightKg: 85),
        ],
      ).first.when,
      DateTime(2026, 1, 26, 9),
    );
  });

  test('sync schedules on change and asks permission only once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Future<void> settle() => Future.delayed(const Duration(milliseconds: 20));

    final app = AppState(prefs, clock: () => DateTime(2026, 1, 5, 8));
    final scheduler = _FakeScheduler();
    final sync = ReminderSync(app, scheduler, prefs, debounce: Duration.zero);
    addTearDown(sync.dispose);
    await settle();
    expect(scheduler.scheduled.single, isEmpty);
    expect(scheduler.permissionRequests, 0);

    await app.addCheckpoint('Wedding', DateTime(2026, 3, 1));
    await settle();
    expect(scheduler.scheduled.last.single.title, 'Wedding is today');
    expect(scheduler.permissionRequests, 1);

    await app.addCheckpoint('Trip', DateTime(2026, 4, 1));
    await settle();
    expect(scheduler.scheduled.last, hasLength(2));
    expect(scheduler.permissionRequests, 1);

    // Changes that don't move any date leave the schedule alone.
    final count = scheduler.scheduled.length;
    await app.setUserProfile(
      const UserProfile(heightCm: 180, age: 35, sex: Sex.male),
    );
    await settle();
    expect(scheduler.scheduled, hasLength(count));
  });
}
