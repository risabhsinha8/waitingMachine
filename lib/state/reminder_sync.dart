import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reminder_notifications.dart';
import '../services/weigh_in_reminders.dart';
import 'app_state.dart';

/// Keeps the OS's pending weigh-in reminders matching [AppState]: whenever
/// predictions, checkpoints or weigh-ins change, the plan is worked out
/// again and, if it differs, rescheduled.
///
/// Notification permission is asked for once, the first time there's
/// something to remind about (usually right after locking in a prediction
/// or pinning a checkpoint), rather than on first launch.
class ReminderSync {
  ReminderSync(
    this._app,
    this._scheduler,
    this._prefs, {
    Duration debounce = const Duration(milliseconds: 500),
  }) : _debounce = debounce {
    _app.addListener(_changed);
    unawaited(_sync());
  }

  static const _askedKey = 'losertown.v1.remindersAsked';

  final AppState _app;
  final ReminderScheduler _scheduler;
  final SharedPreferences _prefs;
  final Duration _debounce;

  Timer? _timer;
  List<WeighInReminder>? _scheduled;
  Future<void> _running = Future.value();

  void _changed() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_sync()));
  }

  /// Runs one sync at a time, so a slow one can't overwrite a newer plan.
  Future<void> _sync() => _running = _running.then((_) async {
    final plan = planWeighInReminders(
      activePredictions: _app.activePredictions,
      checkpoints: _app.checkpoints,
      weightLogs: _app.weightLogs,
      unit: _app.unit,
      now: _app.now(),
    );
    if (_scheduled != null && listEquals(plan, _scheduled)) return;
    try {
      if (plan.isNotEmpty && !(_prefs.getBool(_askedKey) ?? false)) {
        await _prefs.setBool(_askedKey, true);
        await _scheduler.requestPermission();
      }
      await _scheduler.schedule(plan);
      _scheduled = plan;
    } catch (error, stack) {
      debugPrint('Could not schedule reminders: $error\n$stack');
    }
  });

  /// Works the plan out again now, e.g. when the app returns to the
  /// foreground on a new day.
  void refresh() => _changed();

  void dispose() {
    _timer?.cancel();
    _app.removeListener(_changed);
  }
}
