import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'weigh_in_reminders.dart';

/// Hands [WeighInReminder]s to the OS.
abstract class ReminderScheduler {
  /// Replaces every pending reminder with [reminders].
  Future<void> schedule(List<WeighInReminder> reminders);

  /// Asks to show notifications; true if allowed.
  Future<bool> requestPermission();

  /// Counts the times the user opened the app from a reminder, including
  /// the launch itself.
  ValueListenable<int> get taps;
}

/// Local notifications on Android and iOS. The web build has none.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = ValueNotifier(0);

  @override
  ValueListenable<int> get taps => _taps;

  /// Android shows one line unless told to expand to the whole [body].
  static NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'weigh_in',
      'Weigh-in reminders',
      channelDescription:
          'On the days your predictions and checkpoints fall due',
      styleInformation: BigTextStyleInformation(body),
    ),
    iOS: const DarwinNotificationDetails(),
  );

  /// Null where notifications aren't supported, or if setup fails.
  static Future<LocalReminderScheduler?> create() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    try {
      tz.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));

      final plugin = FlutterLocalNotificationsPlugin();
      final scheduler = LocalReminderScheduler._(plugin);
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Asked for when there's first something to remind about.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (_) => scheduler._taps.value++,
      );
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) scheduler._taps.value++;
      return scheduler;
    } catch (error, stack) {
      debugPrint('Reminders unavailable: $error\n$stack');
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission(),
      TargetPlatform.iOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true),
      _ => false,
    };
    return granted ?? false;
  }

  @override
  Future<void> schedule(List<WeighInReminder> reminders) async {
    await _plugin.cancelAllPendingNotifications();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.when, tz.local),
        notificationDetails: _details(r.body),
        // A reminder a few minutes late is fine; exact alarms need a
        // special permission on Android 14+.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
