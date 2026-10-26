import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/app.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/losertown_math.dart';
import 'package:losertown/state/app_state.dart';
import 'package:losertown/utils/units.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = UserProfile(heightCm: 180, age: 35, sex: Sex.male);
final today = DateTime(2026, 10, 26, 9);

Future<AppState> makeState({List<(int, double)> logs = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState(
    await SharedPreferences.getInstance(),
    clock: () => today,
  );
  await app.setUserProfile(profile);
  for (final (dayOffset, kg) in logs) {
    await app.addWeightLog(kg, date: DateTime(2026, 10, 26 + dayOffset, 7));
  }
  return app;
}

/// Opens the app on [tab] and records platform calls (haptics).
Future<List<MethodCall>> pumpApp(
  WidgetTester tester,
  AppState app, {
  String tab = 'Weight Log',
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.pumpWidget(LosertownApp(appState: app));
  await tester.pumpAndSettle();
  if (tab != 'Simulator') {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }
  return calls;
}

Finder visible(Finder f) => f.hitTestable();

bool hadMediumImpact(List<MethodCall> calls) => calls.any(
  (c) =>
      c.method == 'HapticFeedback.vibrate' &&
      c.arguments == 'HapticFeedbackType.mediumImpact',
);

void main() {
  testWidgets('one-tap save logs today with a haptic tap', (tester) async {
    final app = await makeState();
    final calls = await pumpApp(tester, app);

    await tester.enterText(
      visible(find.byKey(const Key('log-weight-input'))),
      '82.4',
    );
    await tester.tap(visible(find.byKey(const Key('log-weight-save'))));
    await tester.pumpAndSettle();

    expect(app.weightLogs.single.weightKg, 82.4);
    expect(app.weightLogs.single.date, today);
    expect(hadMediumImpact(calls), isTrue);
    expect(find.text('Logged 82.4 kg'), findsOneWidget);

    // Undo removes it again.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.weightLogs, isEmpty);
  });

  testWidgets('the date picker back-dates a weigh-in', (tester) async {
    final app = await makeState(logs: [(-1, 83)]);
    await pumpApp(tester, app);

    await tester.tap(visible(find.byKey(const Key('log-weight-date'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Tue, Oct 20'), findsOneWidget);

    await tester.tap(visible(find.byKey(const Key('log-weight-save'))));
    await tester.pumpAndSettle();
    expect(app.weightLogs.first.date, DateTime(2026, 10, 20, 12));
    expect(app.weightLogs.first.weightKg, 83); // prefilled from latest
    // The chip resets to today for the next entry.
    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('steppers nudge the prefilled weight', (tester) async {
    final app = await makeState(logs: [(-1, 83)]);
    await pumpApp(tester, app);

    await tester.tap(visible(find.byTooltip('Decrease')));
    await tester.tap(visible(find.byTooltip('Decrease')));
    await tester.tap(visible(find.byKey(const Key('log-weight-save'))));
    await tester.pumpAndSettle();
    expect(app.weightLogs.last.weightKg, closeTo(82.8, 1e-9));
  });

  testWidgets('history shows scale and 7-day trend weights', (tester) async {
    final app = await makeState(logs: [(-2, 80), (-1, 82), (0, 80.4)]);
    await pumpApp(tester, app);

    final smoothed = LosertownMath.smoothWeights(app.weightLogs);
    final newest = app.weightLogs.last;
    final row = find.byKey(ValueKey('log-row-${newest.id}'));
    expect(
      find.descendant(of: row, matching: find.text('80.4 kg')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          Units.format(smoothed.last.smoothedWeightKg, WeightUnit.kg),
        ),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text('Scale')), findsOne);
    expect(
      find.descendant(of: row, matching: find.text('7-day trend')),
      findsOne,
    );
    // Newest first.
    final rows = app.weightLogs.reversed
        .map((l) => tester.getTopLeft(find.byKey(ValueKey('log-row-${l.id}'))))
        .map((o) => o.dy)
        .toList();
    expect(rows, orderedEquals([...rows]..sort()));
  });

  testWidgets('swipe deletes an accidental log, with undo', (tester) async {
    final app = await makeState(logs: [(-1, 80), (0, 18)]);
    await pumpApp(tester, app);
    final typo = app.weightLogs.last;

    await tester.drag(
      find.byKey(ValueKey('log-row-${typo.id}')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(app.weightLogs.map((l) => l.weightKg), [80]);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.weightLogs.map((l) => l.id), contains(typo.id));
  });

  testWidgets('the + button opens a quick-log sheet from any tab', (
    tester,
  ) async {
    final app = await makeState();
    final calls = await pumpApp(tester, app, tab: 'Simulator');

    await tester.tap(visible(find.byKey(const Key('quick-log-button'))));
    await tester.pumpAndSettle();
    expect(find.text('Log weight'), findsOneWidget);

    await tester.enterText(
      visible(find.byKey(const Key('log-weight-input'))),
      '90',
    );
    await tester.tap(visible(find.byKey(const Key('log-weight-save'))));
    await tester.pumpAndSettle();

    expect(app.weightLogs.single.weightKg, 90);
    expect(hadMediumImpact(calls), isTrue);
    expect(find.text('Log weight'), findsNothing); // sheet closed
  });
}
