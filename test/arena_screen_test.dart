import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/app.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/screens/simulator/lock_in.dart';
import 'package:losertown/services/losertown_math.dart';
import 'package:losertown/state/app_state.dart';
import 'package:losertown/ui/labels.dart';
import 'package:losertown/utils/units.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = UserProfile(heightCm: 180, age: 35, sex: Sex.male);
final created = DateTime(2026, 10, 5, 8);
final today = DateTime(2026, 10, 26, 9);

class Arena {
  Arena(this.app, this.ids);
  final AppState app;
  final Map<String, String> ids;
}

/// Four predictions locked in three weeks ago, plus daily weigh-ins that
/// follow 'Lazy 2000' with zero-mean noise.
Future<Arena> makeArena({
  bool withLogs = true,
  bool withPredictions = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  var now = created;
  final app = AppState(await SharedPreferences.getInstance(), clock: () => now);
  await app.setUserProfile(profile);
  final ids = <String, String>{};
  if (withPredictions) {
    for (final (name, kcal) in [
      ('Strict 1600', 1600.0),
      ('Lazy 2000', 2000.0),
      ('Cruise 2400', 2400.0),
      ('Crash 1200', 1200.0),
    ]) {
      final p = await app.addPrediction(
        name: name,
        dailyCalories: kcal,
        activityLevel: ActivityLevel.lightlyActive,
        startWeightKg: 100,
      );
      ids[name] = p.id;
    }
  }
  if (withLogs) {
    final lazy = app.predictionById(ids['Lazy 2000']!)!;
    const noise = [0.3, -0.2, 0.1, -0.3, 0.2, -0.1, 0.0];
    for (var d = 0; d <= 21; d++) {
      final date = DateTime(2026, 10, 5 + d, 7);
      await app.addWeightLog(
        LosertownMath.expectedWeightOn(lazy, date) + noise[d % 7],
        date: date,
      );
    }
  }
  now = today;
  return Arena(app, ids);
}

Future<void> openArena(WidgetTester tester, AppState app) async {
  // Tall phone so every card is built.
  tester.view.physicalSize = const Size(1080, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(LosertownApp(appState: app));
  await tester.pumpAndSettle();
  await tester.tap(find.text('The Arena'));
  await tester.pumpAndSettle();
}

Finder card(String id) => find.byKey(ValueKey('prediction-card-$id'));

Finder inCard(String id, Finder matching) =>
    find.descendant(of: card(id), matching: matching);

int selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('empty state offers to create a prediction and log weight', (
    tester,
  ) async {
    final arena = await makeArena(withLogs: false, withPredictions: false);
    await openArena(tester, arena.app);

    expect(find.byKey(const Key('timeline-hero-empty')), findsOneWidget);
    expect(find.byKey(const Key('hero-log-weight')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hero-create-prediction')));
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 0);
  });

  testWidgets('quick action logs a weigh-in', (tester) async {
    final arena = await makeArena(withLogs: false);
    await openArena(tester, arena.app);

    expect(find.byKey(const Key('hero-create-prediction')), findsNothing);
    await tester.tap(find.byKey(const Key('hero-log-weight')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('log-weight-input')), '99.5');
    await tester.tap(find.byKey(const Key('log-weight-save')));
    await tester.pumpAndSettle();

    expect(arena.app.weightLogs.single.weightKg, 99.5);
    expect(arena.app.weightLogs.single.date, today);
    // One weigh-in is still not enough to claim a timeline.
    expect(find.textContaining('(1 so far)'), findsOneWidget);
  });

  testWidgets('hero names the closest timeline and the implied intake', (
    tester,
  ) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final evaluation = arena.app.evaluation!;
    final lazy = arena.ids['Lazy 2000']!;

    expect(evaluation.byPosition.first.predictionId, lazy);
    expect(evaluation.byPace.first.predictionId, lazy);
    expect(find.text('‘Lazy 2000’'), findsOneWidget);
    expect(find.textContaining("of today's projected weight."), findsOneWidget);

    final implied = evaluation.byPace.first.impliedDailyCalories!;
    expect(implied, closeTo(2000, 100));
    final shown = formatKcal((implied / 10).round() * 10.0);
    expect(find.textContaining('implies ~$shown/day'), findsOneWidget);
    expect(find.textContaining('Your 14-day pace (-0.'), findsOneWidget);
  });

  testWidgets('cards are ranked by match and colour-coded by drift', (
    tester,
  ) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final ranked = [
      for (final e in arena.app.evaluation!.byPosition) e.predictionId,
    ];

    final tops = [for (final id in ranked) tester.getTopLeft(card(id)).dy];
    expect(tops, orderedEquals([...tops]..sort()));

    final lazy = arena.ids['Lazy 2000']!;
    final crash = arena.ids['Crash 1200']!;
    expect(inCard(lazy, find.text('Sticking To It')), findsOneWidget);
    expect(inCard(crash, find.text('Off Course')), findsOneWidget);
    expect(
      inCard(lazy, find.text('2,000 kcal/day • Lightly Active')),
      findsOneWidget,
    );
    expect(inCard(lazy, find.text('Projected today')), findsOneWidget);
    expect(inCard(lazy, find.text('Actual trend')), findsOneWidget);
    expect(inCard(lazy, find.text('Created Oct 5, 2026')), findsOneWidget);
  });

  testWidgets('swipe left archives with undo, keeping its color', (
    tester,
  ) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final lazy = arena.ids['Lazy 2000']!;
    final before = arena.app.predictionById(lazy)!;

    await tester.drag(card(lazy), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(arena.app.predictionById(lazy)!.isArchived, isTrue);
    expect(arena.app.activePredictions, hasLength(3));
    expect(card(lazy), findsNothing);
    expect(find.text('Archived ‘Lazy 2000’'), findsOneWidget);
    // The archive starts collapsed.
    expect(find.text('Archive (1)'), findsOneWidget);
    expect(find.byKey(ValueKey('archived-tile-$lazy')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(arena.app.predictionById(lazy), before);
    expect(card(lazy), findsOneWidget);
    expect(find.text('Archive (1)'), findsNothing);
  });

  testWidgets('delete from the menu removes it with undo', (tester) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final lazy = arena.ids['Lazy 2000']!;
    final originalOrder = [for (final p in arena.app.predictions) p.id];

    await tester.tap(inCard(lazy, find.byKey(const Key('prediction-menu'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(arena.app.predictionById(lazy), isNull);
    expect(find.text('Deleted ‘Lazy 2000’'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect([for (final p in arena.app.predictions) p.id], originalOrder);
    expect(card(lazy), findsOneWidget);
  });

  testWidgets('re-anchor restarts from today at the trend weight', (
    tester,
  ) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final crash = arena.ids['Crash 1200']!;
    final before = arena.app.predictionById(crash)!;

    await tester.tap(inCard(crash, find.byKey(const Key('prediction-menu'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-anchor to Today'));
    await tester.pumpAndSettle();

    final after = arena.app.predictionById(crash)!;
    expect(after.createdAt, today);
    expect(after.startWeightKg, arena.app.currentWeightKg);
    expect(after.dailyCalories, before.dailyCalories);
    expect(after.activityLevel, before.activityLevel);
    expect(inCard(crash, find.text('Sticking To It')), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(arena.app.predictionById(crash), before);
  });

  testWidgets('tapping a card shows its weeks against logged weights', (
    tester,
  ) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final lazy = arena.ids['Lazy 2000']!;

    await tester.tap(inCard(lazy, find.text('Lazy 2000')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('details-sheet'));
    expect(sheet, findsOneWidget);
    expect(find.text('Projected'), findsOneWidget);
    expect(find.text('Logged'), findsOneWidget);
    expect(find.textContaining('4 of 4 weeks logged'), findsOneWidget);

    // Week 3 is Oct 26: today's row, with a logged weight and a delta.
    final week3 = find.byKey(const ValueKey('details-week-3'));
    expect(
      find.descendant(of: week3, matching: find.text('Oct 26')),
      findsOneWidget,
    );
    expect(find.descendant(of: week3, matching: find.text('—')), findsNothing);
    // Next week hasn't happened yet.
    final week4 = find.byKey(const ValueKey('details-week-4'));
    expect(
      find.descendant(of: week4, matching: find.text('—')),
      findsNWidgets(2),
    );
  });

  testWidgets('Open in Simulator loads the prediction there', (tester) async {
    final arena = await makeArena();
    await openArena(tester, arena.app);
    final lazy = arena.ids['Lazy 2000']!;

    await tester.tap(inCard(lazy, find.byKey(const Key('prediction-menu'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Simulator'));
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(find.text('Tweaking “Lazy 2000”'), findsOneWidget);
  });

  group('timeline chart', () {
    LineChartData chartData(WidgetTester tester) =>
        tester.widget<LineChart>(find.byType(LineChart)).data;

    bool isCursor(LineChartBarData b) => b.barWidth == 0 && !b.dotData.show;

    testWidgets('plots each prediction dashed under a solid trend line', (
      tester,
    ) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      final bars = chartData(tester).lineBarsData;

      final predictionBars = bars.where((b) => b.dashArray != null).toList();
      expect(predictionBars, hasLength(4));
      // Four distinct colors.
      expect(predictionBars.map((b) => b.color).toSet(), hasLength(4));

      // The trend is drawn last (on top), solid, bold, with dots.
      final trend = bars.last;
      expect(trend.dashArray, isNull);
      expect(trend.barWidth, 3);
      expect(trend.dotData.show, isTrue);
      expect(trend.spots, hasLength(22));
    });

    testWidgets('window selector changes the plotted range', (tester) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      // Three weeks of history fit the 30-day window, so it's the default.
      expect(chartData(tester).maxX, 30 + 7);

      await tester.tap(find.text('90D'));
      await tester.pumpAndSettle();
      expect(chartData(tester).maxX, 90 + 22);
    });

    testWidgets('filter chips hide and show predictions', (tester) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      int dashed() => chartData(
        tester,
      ).lineBarsData.where((b) => b.dashArray != null).length;
      final crash = arena.ids['Crash 1200']!;
      // The chart sits below the timeline hero.
      await tester.ensureVisible(find.byKey(ValueKey('chart-filter-$crash')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('chart-filter-$crash')));
      await tester.pumpAndSettle();
      expect(dashed(), 3);

      await tester.tap(find.byKey(ValueKey('chart-filter-$crash')));
      await tester.pumpAndSettle();
      expect(dashed(), 4);
    });

    testWidgets('tooltip lists the date, actual trend and every projection', (
      tester,
    ) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      final data = chartData(tester);
      final cursorIndex = data.lineBarsData.indexWhere(isCursor);
      final cursor = data.lineBarsData[cursorIndex];
      // Today is x = 30 in the default 30-day window.
      final spot = cursor.spots.firstWhere((s) => s.x == 30);

      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(cursor, cursorIndex, spot),
      ]);
      final item = items.single!;
      final text =
          item.text + (item.children ?? []).map((c) => c.toPlainText()).join();

      expect(text, startsWith('Oct 26, 2026'));
      final trend = arena.app.smoothedWeights.last.smoothedWeightKg;
      expect(
        text,
        contains('${Units.format(trend, WeightUnit.kg)}  actual trend'),
      );
      expect(text, contains('scale'));
      for (final p in arena.app.predictions) {
        final kg = LosertownMath.expectedWeightOn(p, DateTime(2026, 10, 26));
        expect(text, contains('${Units.format(kg, WeightUnit.kg)}  ${p.name}'));
      }
    });
  });

  group('archive', () {
    Finder archivedTile(String id) => find.byKey(ValueKey('archived-tile-$id'));

    Future<void> lockInFromSimulator(WidgetTester tester) async {
      await tester.tap(find.text('Simulator').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('lock-in-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock-in-arena-full')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lock-in-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock-in-full-note')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('lock-in-name')), 'Fresh');
      await tester.tap(find.byKey(const Key('lock-in-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('the header shows how many Arena places are taken', (
      tester,
    ) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      expect(find.text('In the Arena'), findsOneWidget);
      expect(find.text('4/4'), findsOneWidget);
      for (final id in arena.ids.values) {
        expect(
          inCard(id, find.byKey(const Key('card-series-key'))),
          findsOneWidget,
        );
      }
    });

    testWidgets('locking in with a full Arena archives the furthest-off one', (
      tester,
    ) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      await lockInFromSimulator(tester);

      expect(find.byKey(const Key('make-room-sheet')), findsOneWidget);
      expect(find.text('Furthest off'), findsOneWidget);
      final crash = arena.ids['Crash 1200']!;
      final selected = tester.widget<RadioListTile<String>>(
        find.byKey(ValueKey('make-room-$crash')),
      );
      expect(selected.groupValue, crash);

      await tester.tap(find.byKey(const Key('make-room-confirm')));
      await tester.pumpAndSettle();
      expect(arena.app.predictionById(crash)!.isArchived, isTrue);
      expect(arena.app.activePredictions.map((p) => p.name), contains('Fresh'));
      expect(arena.app.activePredictions, hasLength(4));
      expect(
        find.text('Locked in “Fresh” · ‘Crash 1200’ archived'),
        findsOneWidget,
      );
    });

    testWidgets('or saves the new one straight to the archive', (tester) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      await lockInFromSimulator(tester);

      await tester.tap(find.byKey(const Key('make-room-save-archived')));
      await tester.pumpAndSettle();
      expect(
        arena.app.activePredictions.map((p) => p.name),
        isNot(contains('Fresh')),
      );
      expect(arena.app.archivedPredictions.single.name, 'Fresh');
      expect(find.text('Saved “Fresh” to the archive'), findsOneWidget);
    });

    testWidgets('backing out of the sheet saves nothing', (tester) async {
      final arena = await makeArena();
      await openArena(tester, arena.app);
      await lockInFromSimulator(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(arena.app.predictions, hasLength(4));
    });

    testWidgets('restore goes straight back when there is room', (
      tester,
    ) async {
      final arena = await makeArena();
      final lazy = arena.ids['Lazy 2000']!;
      await arena.app.archivePrediction(lazy);
      await openArena(tester, arena.app);
      expect(find.text('3/4'), findsOneWidget);

      await tester.tap(find.byKey(const Key('archive-toggle')));
      await tester.pumpAndSettle();
      expect(archivedTile(lazy), findsOneWidget);
      expect(find.textContaining('Today: Sticking To It'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('restore-$lazy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('make-room-sheet')), findsNothing);
      expect(arena.app.predictionById(lazy)!.isArchived, isFalse);
      expect(card(lazy), findsOneWidget);
      expect(find.text('Restored ‘Lazy 2000’ to the Arena'), findsOneWidget);
    });

    testWidgets('restoring into a full Arena swaps, with undo', (tester) async {
      final arena = await makeArena();
      final app = arena.app;
      final extra = await app.addPrediction(
        name: 'Old idea',
        dailyCalories: 1800,
        activityLevel: ActivityLevel.lightlyActive,
        startWeightKg: 100,
        archived: true,
      );
      await openArena(tester, app);
      await tester.tap(find.byKey(const Key('archive-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('restore-${extra.id}')));
      await tester.pumpAndSettle();

      // Restoring offers no "save to archive" — it's already there.
      expect(find.byKey(const Key('make-room-save-archived')), findsNothing);
      final strict = arena.ids['Strict 1600']!;
      final before = app.predictionById(strict)!;
      await tester.tap(find.byKey(ValueKey('make-room-$strict')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('make-room-confirm')));
      await tester.pumpAndSettle();
      expect(app.predictionById(strict)!.isArchived, isTrue);
      expect(app.predictionById(extra.id)!.colorSlot, before.colorSlot);
      expect(
        find.text('Swapped in ‘Old idea’ · ‘Strict 1600’ archived'),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.predictionById(extra.id)!.isArchived, isTrue);
      expect(app.predictionById(strict), before);
    });

    testWidgets('swiping an archived row deletes it, with undo', (
      tester,
    ) async {
      final arena = await makeArena();
      final lazy = arena.ids['Lazy 2000']!;
      await arena.app.archivePrediction(lazy);
      await openArena(tester, arena.app);
      await tester.tap(find.byKey(const Key('archive-toggle')));
      await tester.pumpAndSettle();

      await tester.drag(archivedTile(lazy), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(arena.app.predictionById(lazy), isNull);
      expect(find.text('Deleted ‘Lazy 2000’'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(arena.app.predictionById(lazy)!.isArchived, isTrue);
    });

    testWidgets('an empty Arena with an archive says so', (tester) async {
      final arena = await makeArena();
      for (final id in arena.ids.values) {
        await arena.app.archivePrediction(id);
      }
      await openArena(tester, arena.app);
      expect(
        find.textContaining('all 4 of your predictions are archived'),
        findsOneWidget,
      );
      expect(find.text('Archive (4)'), findsOneWidget);
    });
  });

  group('near-duplicates', () {
    test('flags an Arena line the new one would sit on', () async {
      final arena = await makeArena(withLogs: false);
      final lazy = arena.app.predictionById(arena.ids['Lazy 2000']!)!;
      final todayKg = LosertownMath.expectedWeightOn(lazy, today);
      PredictionSnapshot? check({
        double kcal = 2030,
        ActivityLevel level = ActivityLevel.lightlyActive,
        double? startKg,
        double? targetKg,
      }) => findOverlappingPrediction(
        arena.app.activePredictions,
        dailyCalories: kcal,
        activityLevel: level,
        startWeightKg: startKg ?? todayKg + 0.5,
        targetWeightKg: targetKg,
        on: today,
      );

      expect(check()?.id, lazy.id);
      expect(check(kcal: 2100), isNull);
      expect(check(level: ActivityLevel.sedentary), isNull);
      expect(check(startKg: todayKg - 2), isNull);
      expect(check(targetKg: 85), isNull);
    });

    testWidgets('the Lock In dialog warns about it', (tester) async {
      final arena = await makeArena(withLogs: false);
      final lazy = arena.app.predictionById(arena.ids['Lazy 2000']!)!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LockInDialog(
              suggestedName: 'x',
              summary: 'y',
              similarTo: lazy,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('lock-in-similar')), findsOneWidget);
      expect(
        find.textContaining('Nearly identical to ‘Lazy 2000’'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('lock-in-full-note')), findsNothing);
    });
  });
}
