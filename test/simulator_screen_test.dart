import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/app.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = UserProfile(heightCm: 180, age: 35, sex: Sex.male);

Future<AppState> makeState({
  UserProfile? userProfile = profile,
  double? loggedKg,
}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState(await SharedPreferences.getInstance());
  if (userProfile != null) await app.setUserProfile(userProfile);
  if (loggedKg != null) await app.addWeightLog(loggedKg);
  return app;
}

Future<void> pumpApp(WidgetTester tester, AppState app) async {
  // A typical phone viewport.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(LosertownApp(appState: app));
  await tester.pumpAndSettle();
}

String outcomeText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('summary-outcome')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join(' | ');

/// Scrolls [finder] into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Finder sliderIn(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Slider));

void main() {
  testWidgets('shell has three tabs', (tester) async {
    await pumpApp(tester, await makeState());
    expect(find.text('Simulator'), findsNWidgets(2)); // app bar + nav bar
    expect(find.text('The Arena'), findsOneWidget);
    expect(find.text('Weight Log'), findsOneWidget);

    await tester.tap(find.text('The Arena'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-in-fab')), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('first launch asks for a profile and persists it', (
    tester,
  ) async {
    final app = await makeState(userProfile: null);
    await pumpApp(tester, app);

    expect(find.text('Your baseline'), findsOneWidget);
    await tester.tap(find.text('Female'));
    await tester.enterText(find.byKey(const Key('profile-age')), '29');
    await tester.enterText(find.byKey(const Key('profile-height-cm')), '165');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(
      app.userProfile,
      const UserProfile(heightCm: 165, age: 29, sex: Sex.female),
    );
    expect(find.text('Female · 29 y · 165 cm'), findsOneWidget);
    expect(find.byKey(const Key('summary-outcome')), findsOneWidget);
  });

  testWidgets('baseline chip edits the profile', (tester) async {
    final app = await makeState();
    await pumpApp(tester, app);

    await tester.tap(find.byKey(const Key('baseline-chip')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-age')), '40');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(app.userProfile!.age, 40);
    expect(find.text('Male · 40 y · 180 cm'), findsOneWidget);
  });

  testWidgets('starting weight defaults to the latest weigh-in', (
    tester,
  ) async {
    await pumpApp(tester, await makeState(loggedKg: 92.4));
    expect(
      find.descendant(
        of: find.byKey(const Key('start-weight')),
        matching: find.text('92.4 kg'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('unit toggle switches every weight to lbs', (tester) async {
    final app = await makeState(loggedKg: 92.4);
    await pumpApp(tester, app);

    await tester.tap(find.text('lbs').first);
    await tester.pumpAndSettle();

    expect(app.unit, WeightUnit.lbs);
    expect(find.text('203.7 lbs'), findsWidgets);
    expect(find.text('5′11″'), findsNothing); // part of the chip label
    expect(find.text('Male · 35 y · 5′11″'), findsOneWidget);
  });

  testWidgets('calorie slider and activity chips update the projection live', (
    tester,
  ) async {
    await pumpApp(tester, await makeState(loggedKg: 100));
    final initial = outcomeText(tester);

    final slider = sliderIn('daily-calories');
    await tester.dragFrom(tester.getCenter(slider), const Offset(-60, 0));
    await tester.pump();
    final afterSlider = outcomeText(tester);
    expect(afterSlider, isNot(initial));

    await tapVisible(tester, find.byKey(const Key('activity-veryActive')));
    await tester.pump();
    expect(outcomeText(tester), isNot(afterSlider));
  });

  testWidgets('starting weight accepts a typed value', (tester) async {
    await pumpApp(tester, await makeState(loggedKg: 92.4));

    await tester.tap(find.text('92.4 kg').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '88');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(find.text('88.0 kg'), findsWidgets);
  });

  testWidgets('milestone and target rows are highlighted', (tester) async {
    await pumpApp(tester, await makeState(loggedKg: 100));
    await tapVisible(tester, find.byKey(const Key('target-switch')));
    await tester.pump();

    final list = find.descendant(
      of: find.byKey(const Key('projection-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Below 95 kg'),
      300,
      scrollable: list,
    );
    expect(find.text('Below 95 kg'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Target reached · 90.0 kg'),
      300,
      scrollable: list,
    );
    expect(find.text('Target reached · 90.0 kg'), findsOneWidget);
  });

  testWidgets('Lock In saves a named prediction', (tester) async {
    final app = await makeState(loggedKg: 95);
    await pumpApp(tester, app);

    await tapVisible(tester, find.byKey(const Key('lock-in-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lock-in-name')),
      'Strict 1600',
    );
    await tester.tap(find.byKey(const Key('lock-in-save')));
    await tester.pumpAndSettle();

    final saved = app.predictions.single;
    expect(saved.name, 'Strict 1600');
    expect(saved.startWeightKg, 95);
    expect(saved.dailyCalories, 2000);
    expect(saved.activityLevel, ActivityLevel.lightlyActive);
    expect(saved.horizonWeeks, 52);
    expect(find.text('Locked in “Strict 1600”'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('a saved prediction can be loaded back or cloned', (
    tester,
  ) async {
    final app = await makeState(loggedKg: 95);
    await app.addPrediction(
      name: 'Lazy 1900',
      dailyCalories: 1900,
      activityLevel: ActivityLevel.veryActive,
      startWeightKg: 98,
    );
    await pumpApp(tester, app);
    // Scroll deep into the projection so loading must bring controls back.
    await tester.drag(
      find.byKey(const Key('projection-list')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saved-predictions-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clone'));
    await tester.pumpAndSettle();
    expect(app.predictions.map((p) => p.name), [
      'Lazy 1900',
      'Lazy 1900 (copy)',
    ]);

    await tester.tap(find.text('Load').last); // oldest is listed last
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loaded-banner')), findsOneWidget);
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('projection-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(list.position.pixels, 0);
    expect(find.text('Tweaking “Lazy 1900”'), findsOneWidget);
    expect(find.text('1,900 kcal'), findsOneWidget);
    expect(find.text('98.0 kg'), findsWidgets);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('activity-veryActive')),
    );
    expect(chip.selected, isTrue);

    // Locking in a tweak saves a new prediction and clears the banner.
    await tapVisible(tester, find.byKey(const Key('lock-in-button')));
    await tester.pumpAndSettle();
    expect(find.text('Lazy 1900 (tweaked)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lock-in-save')));
    await tester.pumpAndSettle();
    expect(app.predictions, hasLength(3));
    expect(find.byKey(const Key('loaded-banner')), findsNothing);
  });

  testWidgets('floating Lock In appears only once the card scrolls away', (
    tester,
  ) async {
    final app = await makeState(loggedKg: 95);
    await pumpApp(tester, app);

    double fabScale() => tester
        .widget<AnimatedScale>(
          find.ancestor(
            of: find.byKey(const Key('lock-in-fab')),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;

    expect(fabScale(), 0);
    await tester.drag(
      find.byKey(const Key('projection-list')),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expect(fabScale(), 1);

    await tester.tap(find.byKey(const Key('lock-in-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lock-in-save')));
    await tester.pumpAndSettle();
    expect(app.predictions, hasLength(1));

    await tester.drag(
      find.byKey(const Key('projection-list')),
      const Offset(0, 3000),
    );
    await tester.pumpAndSettle();
    expect(fabScale(), 0);
  });

  testWidgets('wide layouts pin the controls beside the rows', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LosertownApp(appState: await makeState(loggedKg: 95)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lock-in-button')), findsOneWidget);
    expect(find.byKey(const Key('lock-in-fab')), findsNothing);
    expect(find.byKey(const Key('week-0')), findsOneWidget);
  });
}
