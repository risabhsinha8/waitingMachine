import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/reminder_notifications.dart';
import 'state/app_state.dart';
import 'state/reminder_sync.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Errors are logged rather than crashing the app; release builds show a
  // quiet placeholder instead of the red debug screen for a broken widget.
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  if (kReleaseMode) ErrorWidget.builder = (_) => const _BrokenWidget();

  final AppState appState;
  try {
    appState = await AppState.load();
  } catch (error, stack) {
    // Usually storage the browser won't give us (some private modes).
    debugPrint('Could not open storage: $error\n$stack');
    runApp(const _StartupFailedApp());
    return;
  }

  // Weigh-in reminders on the days predictions and checkpoints fall due.
  // Android and iOS only; the app works the same without them.
  final reminders = await LocalReminderScheduler.create();
  if (reminders != null) {
    final sync = ReminderSync(
      appState,
      reminders,
      await SharedPreferences.getInstance(),
    );
    // Today's reminder drops off once its hour passes; catch up on resume.
    AppLifecycleListener(onResume: sync.refresh);
  }

  runApp(LosertownApp(appState: appState, reminderTaps: reminders?.taps));
}

class _BrokenWidget extends StatelessWidget {
  const _BrokenWidget();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Something went wrong showing this.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _StartupFailedApp extends StatelessWidget {
  const _StartupFailedApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Losertown',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sd_card_alert_outlined,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Losertown can’t save data here',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your browser is blocking local storage, which is where '
                    'your weigh-ins and predictions live. Turn off private '
                    'browsing or allow site data, then reload.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
