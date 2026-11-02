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

/// Scrolls the weight log until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    // The list's own Scrollable; text fields inside it have theirs too.
    scrollable: find
        .descendant(
          of: find.byKey(const Key('weight-log-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

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
    // The rank card and entry form sit above the history.
    await scrollTo(tester, row);
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
    await scrollTo(
      tester,
      find.byKey(ValueKey('log-row-${app.weightLogs.first.id}')),
    );
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
    await scrollTo(tester, find.byKey(ValueKey('log-row-${typo.id}')));

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

  group('rank card', () {
    testWidgets('is a mystery until the first weigh-in', (tester) async {
      await pumpApp(tester, await makeState());
      expect(find.byKey(const Key('rank-card')), findsOneWidget);
      expect(find.text('Rank unknown'.toUpperCase()), findsOneWidget);
      expect(find.text('Mystery Hero'), findsOneWidget);
      expect(find.byKey(const Key('rank-progress')), findsNothing);
    });

    testWidgets('shows the rank and what it takes to rank up', (tester) async {
      // 87.5 kg at 180 cm: BMI 27.0, Elite Ranger; Legend below 81 kg.
      await pumpApp(tester, await makeState(logs: [(0, 87.5)]));
      expect(find.text('Elite Ranger'), findsOneWidget);
      expect(find.text('LEVEL 5 OF 6'), findsOneWidget);
      expect(find.text('BMI 27.0'), findsOneWidget);
      expect(
        find.text('Lose 6.5 kg to become Legend of Losertown'),
        findsOneWidget,
      );
    });

    testWidgets('tapping it opens the ladder with your rank marked', (
      tester,
    ) async {
      await pumpApp(tester, await makeState(logs: [(0, 87.5)]));
      await tester.tap(find.byKey(const Key('rank-card')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rank-ladder')), findsOneWidget);
      final mine = find.byKey(const ValueKey('ladder-eliteRanger'));
      expect(
        find.descendant(of: mine, matching: find.text('You')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: mine,
          matching: find.text('81 kg – 89 kg · BMI 25–27.5'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a weigh-in that ranks up says so, with a big haptic', (
      tester,
    ) async {
      // BMI 27.6: Journeyman Burner, one level below Elite Ranger.
      final app = await makeState(logs: [(-1, 89.5)]);
      final calls = await pumpApp(tester, app);
      expect(find.text('Journeyman Burner'), findsOneWidget);

      await tester.enterText(
        visible(find.byKey(const Key('log-weight-input'))),
        '85',
      );
      await tester.tap(visible(find.byKey(const Key('log-weight-save'))));
      await tester.pumpAndSettle();

      expect(
        find.text('Level up! You’re now Elite Ranger · Logged 85.0 kg'),
        findsOneWidget,
      );
      expect(find.text('Elite Ranger'), findsOneWidget);
      expect(
        calls.any((c) => c.arguments == 'HapticFeedbackType.heavyImpact'),
        isTrue,
      );
    });
  });
}
