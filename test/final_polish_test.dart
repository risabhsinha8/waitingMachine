import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/app.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/demo_data.dart';
import 'package:losertown/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = UserProfile(heightCm: 180, age: 35, sex: Sex.male);
final today = DateTime(2026, 10, 26, 9);

Future<AppState> makeState({bool withProfile = true}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState(
    await SharedPreferences.getInstance(),
    clock: () => today,
  );
  if (withProfile) await app.setUserProfile(profile);
  return app;
}

/// Pumps the app and returns the haptic feedback types fired.
Future<List<String>> pumpApp(
  WidgetTester tester,
  AppState app, {
  Size size = const Size(1080, 2340),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final haptics = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    // Pickers also send a bare vibrate (null arguments).
    if (call.method == 'HapticFeedback.vibrate' && call.arguments != null) {
      haptics.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.pumpWidget(LosertownApp(appState: app));
  await tester.pumpAndSettle();
  return haptics;
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> openProfileSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('baseline-chip')));
  await tester.pumpAndSettle();
}

Future<void> tapInSheet(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Finder visible(Finder f) => f.hitTestable();

void main() {
  group('demo data', () {
    testWidgets('loads from the first-launch sheet without a prompt', (
      tester,
    ) async {
      final app = await makeState(withProfile: false);
      await pumpApp(tester, app);
      expect(find.text('Your baseline'), findsOneWidget);

      await tapInSheet(tester, const Key('load-demo'));

      expect(app.predictions, hasLength(3));
      expect(app.weightLogs, hasLength(DemoData.days));
      expect(app.userProfile, isNotNull);
      expect(find.text('Your baseline'), findsNothing);
      expect(find.text('Loaded demo: 3 predictions, 30 weigh-ins'), findsOne);

      await openTab(tester, 'The Arena');
      expect(find.text('‘Sustainable 1850 kcal’'), findsOneWidget);
    });

    testWidgets('asks before replacing existing data', (tester) async {
      final app = await makeState();
      await app.addWeightLog(100);
      await pumpApp(tester, app);
      await openProfileSheet(tester);

      await tapInSheet(tester, const Key('load-demo'));
      expect(find.text('Load demo data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.weightLogs.single.weightKg, 100);

      await tapInSheet(tester, const Key('load-demo'));
      await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
      await tester.pumpAndSettle();
      expect(app.weightLogs, hasLength(DemoData.days));
    });
  });

  testWidgets('reset all data requires confirmation', (tester) async {
    final app = await makeState();
    await app.addWeightLog(100);
    final haptics = await pumpApp(tester, app);
    await openProfileSheet(tester);

    await tapInSheet(tester, const Key('reset-all'));
    expect(find.textContaining('permanently deletes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.weightLogs, hasLength(1));

    await tapInSheet(tester, const Key('reset-all'));
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
    expect(app.hasAnyData, isFalse);
    expect(find.text('All data cleared'), findsOneWidget);
    expect(find.text('Set up your baseline'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
  });

  group('checkpoints', () {
    Future<AppState> demoState() async {
      final app = await makeState();
      final demo = DemoData.build(now: today);
      await app.replaceAll(
        profile: demo.profile,
        predictions: demo.predictions,
        weightLogs: demo.weightLogs,
      );
      return app;
    }

    testWidgets('pin a goal date and see it on every card', (tester) async {
      final app = await demoState();
      final haptics = await pumpApp(tester, app, size: const Size(1080, 9000));
      await openTab(tester, 'The Arena');
      expect(find.byKey(const Key('checkpoint-row')), findsNothing);

      await tester.tap(find.byKey(const Key('add-checkpoint')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('checkpoint-label')),
        'Beach Trip',
      );
      await tester.tap(find.byKey(const Key('checkpoint-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15')); // Nov 15, in the picker's month
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkpoint-save')));
      await tester.pumpAndSettle();

      expect(app.checkpoints.single.label, 'Beach Trip');
      expect(app.checkpoints.single.date, DateTime(2026, 11, 15));
      expect(find.text('Beach Trip · Nov 15'), findsOneWidget);
      expect(find.byKey(const Key('checkpoint-row')), findsNWidgets(3));
      expect(
        find.text('Checkpoints · if you follow this from today'),
        findsNWidgets(3),
      );
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
    });

    testWidgets('at most three, removable with undo', (tester) async {
      final app = await demoState();
      for (final (label, day) in [('A', 1), ('B', 2), ('C', 3)]) {
        await app.addCheckpoint(label, DateTime(2026, 12, day));
      }
      await pumpApp(tester, app, size: const Size(1080, 9000));
      await openTab(tester, 'The Arena');

      expect(find.byKey(const Key('add-checkpoint')), findsNothing);
      expect(find.text('3 of 3 pinned'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove B'));
      await tester.pumpAndSettle();
      expect(app.checkpoints.map((c) => c.label), ['A', 'C']);
      expect(find.byKey(const Key('add-checkpoint')), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.checkpoints.map((c) => c.label), ['A', 'B', 'C']);
    });
  });

  group('haptics', () {
    testWidgets('calorie slider ticks on each 100 kcal crossed', (
      tester,
    ) async {
      final app = await makeState();
      await app.addWeightLog(95);
      final haptics = await pumpApp(tester, app);

      final slider = find.descendant(
        of: find.byKey(const Key('daily-calories')),
        matching: find.byType(Slider),
      );
      await tester.drag(slider, const Offset(-80, 0));
      await tester.pump();
      expect(haptics, contains('HapticFeedbackType.selectionClick'));
    });

    testWidgets('locking in and archiving a prediction give feedback', (
      tester,
    ) async {
      final app = await makeState();
      await app.addWeightLog(95);
      final haptics = await pumpApp(tester, app, size: const Size(1080, 6000));

      await tester.tap(find.byKey(const Key('lock-in-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lock-in-save')));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.mediumImpact']);

      await openTab(tester, 'The Arena');
      final id = app.predictions.single.id;
      await tester.drag(
        find.byKey(ValueKey('prediction-card-$id')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(app.activePredictions, isEmpty);
      expect(haptics.last, 'HapticFeedbackType.lightImpact');
    });
  });

  group('keyboard', () {
    testWidgets('tapping empty space dismisses it', (tester) async {
      final app = await makeState();
      await app.addWeightLog(95);
      await pumpApp(tester, app);
      await openTab(tester, 'Weight Log');

      await tester.tap(visible(find.byKey(const Key('log-weight-input'))));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('History'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('scrolling a list dismisses it', (tester) async {
      final app = await makeState();
      for (var d = 0; d < 20; d++) {
        await app.addWeightLog(95, date: DateTime(2026, 10, 6 + d));
      }
      await pumpApp(tester, app);
      await openTab(tester, 'Weight Log');

      await tester.tap(visible(find.byKey(const Key('log-weight-input'))));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.drag(
        visible(find.byKey(const Key('weight-log-list'))),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('saving a weigh-in hides it', (tester) async {
      final app = await makeState();
      await pumpApp(tester, app);
      await openTab(tester, 'Weight Log');

      await tester.enterText(
        visible(find.byKey(const Key('log-weight-input'))),
        '91.2',
      );
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(visible(find.byKey(const Key('log-weight-save'))));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(app.weightLogs.single.weightKg, 91.2);
    });
  });
}
