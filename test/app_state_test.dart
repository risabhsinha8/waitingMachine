import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/state/app_state.dart';
import 'package:losertown/utils/units.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = UserProfile(heightCm: 180, age: 35, sex: Sex.male);

void main() {
  late DateTime now;
  late SharedPreferences prefs;

  Future<AppState> createState() async {
    final state = AppState(prefs, clock: () => now);
    await state.setUserProfile(profile);
    return state;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 1, 5, 8);
  });

  test('persists profile, predictions, and logs across reloads', () async {
    final state = await createState();
    await state.addWeightLog(100);
    final p = await state.addPrediction(
      name: 'Cut',
      dailyCalories: 2000,
      activityLevel: ActivityLevel.moderatelyActive,
      targetWeightKg: 85,
    );

    final reloaded = AppState(prefs, clock: () => now);
    expect(reloaded.userProfile, profile);
    expect(reloaded.weightLogs, state.weightLogs);
    expect(reloaded.predictions, [p]);
    expect(reloaded.predictions.single.startWeightKg, 100);
    expect(reloaded.predictions.single.points, hasLength(53));
  });

  test('notifies listeners on mutation', () async {
    final state = await createState();
    var notifications = 0;
    state.addListener(() => notifications++);
    await state.addWeightLog(90);
    await state.addPrediction(
      name: 'x',
      dailyCalories: 2000,
      activityLevel: ActivityLevel.sedentary,
    );
    expect(notifications, 2);
  });

  test('requires a profile and a start weight to add a prediction', () async {
    final bare = AppState(prefs, clock: () => now);
    expect(
      () => bare.addPrediction(
        name: 'x',
        dailyCalories: 2000,
        activityLevel: ActivityLevel.sedentary,
        startWeightKg: 90,
      ),
      throwsStateError,
    );
    final state = await createState();
    expect(
      () => state.addPrediction(
        name: 'x',
        dailyCalories: 2000,
        activityLevel: ActivityLevel.sedentary,
      ),
      throwsStateError,
    );
  });

  test('clones with a new id and identical projection', () async {
    final state = await createState();
    final p = await state.addPrediction(
      name: 'Cut',
      dailyCalories: 2000,
      activityLevel: ActivityLevel.moderatelyActive,
      startWeightKg: 100,
    );
    final copy = await state.clonePrediction(p.id);
    expect(copy.id, isNot(p.id));
    expect(copy.name, 'Cut (copy)');
    expect(copy.points, p.points);
    expect(state.predictions, hasLength(2));
  });

  test('deletes predictions and logs', () async {
    final state = await createState();
    final log = await state.addWeightLog(100);
    final p = await state.addPrediction(
      name: 'x',
      dailyCalories: 2000,
      activityLevel: ActivityLevel.sedentary,
    );
    await state.deletePrediction(p.id);
    await state.deleteWeightLog(log.id);

    final reloaded = AppState(prefs);
    expect(reloaded.predictions, isEmpty);
    expect(reloaded.weightLogs, isEmpty);
  });

  test('re-anchors from today\'s smoothed weight, keeping settings', () async {
    final state = await createState();
    final p = await state.addPrediction(
      name: 'Cut',
      dailyCalories: 2000,
      activityLevel: ActivityLevel.moderatelyActive,
      startWeightKg: 100,
      targetWeightKg: 85,
      weeks: 80,
    );

    for (var d = 0; d <= 30; d++) {
      await state.addWeightLog(
        100 - 0.1 * d,
        date: DateTime(2026, 1, 5 + d, 7),
      );
    }
    now = DateTime(2026, 2, 4, 9);
    final reanchored = await state.reanchorPrediction(p.id);

    expect(reanchored.id, p.id);
    expect(reanchored.name, 'Cut');
    expect(reanchored.dailyCalories, 2000);
    expect(reanchored.targetWeightKg, 85);
    expect(reanchored.horizonWeeks, 80);
    expect(reanchored.createdAt, now);
    expect(reanchored.points.first.date, DateTime(2026, 2, 4));
    expect(reanchored.startWeightKg, state.currentWeightKg);
    expect(reanchored.points.first.projectedWeightKg, state.currentWeightKg);
    expect(state.predictions, [reanchored]);
    expect(
      state.evaluation!.byPosition.single.expectedWeightTodayKg,
      closeTo(state.currentWeightKg!, 1e-9),
    );
  });

  test('keeps weight logs sorted by date', () async {
    final state = await createState();
    await state.addWeightLog(80, date: DateTime(2026, 1, 3));
    await state.addWeightLog(81, date: DateTime(2026, 1, 1));
    await state.addWeightLog(79, date: DateTime(2026, 1, 5));
    expect(state.weightLogs.map((l) => l.weightKg), [81, 80, 79]);
  });

  group('checkpoints', () {
    test('persist sorted by date, capped at three', () async {
      final state = await createState();
      await state.addCheckpoint('  Birthday ', DateTime(2027, 2, 3, 15));
      await state.addCheckpoint('Beach Trip', DateTime(2026, 12, 15));
      await state.addCheckpoint('Wedding', DateTime(2027, 6, 1));

      final reloaded = AppState(prefs);
      expect(reloaded.checkpoints.map((c) => c.label), [
        'Beach Trip',
        'Birthday',
        'Wedding',
      ]);
      expect(reloaded.checkpoints[1].date, DateTime(2027, 2, 3));
      expect(
        () => state.addCheckpoint('Fourth', DateTime(2027, 8, 1)),
        throwsStateError,
      );
    });

    test('remove and restore', () async {
      final state = await createState();
      final c = await state.addCheckpoint('Beach', DateTime(2026, 12, 15));
      await state.removeCheckpoint(c.id);
      expect(AppState(prefs).checkpoints, isEmpty);
      await state.restoreCheckpoint(c);
      expect(AppState(prefs).checkpoints, [c]);
    });
  });

  group('bulk data', () {
    test('replaceAll swaps everything and persists', () async {
      final state = await createState();
      await state.addWeightLog(100);
      const demoProfile = UserProfile(heightCm: 170, age: 30, sex: Sex.female);
      final log = WeightLog(id: 'l', date: DateTime(2026, 1, 1), weightKg: 70);
      final checkpoint = Checkpoint(
        id: 'c',
        label: 'Trip',
        date: DateTime(2026, 3, 1),
      );
      await state.replaceAll(
        profile: demoProfile,
        predictions: const [],
        weightLogs: [log],
        checkpoints: [checkpoint],
      );

      final reloaded = AppState(prefs);
      expect(reloaded.userProfile, demoProfile);
      expect(reloaded.weightLogs, [log]);
      expect(reloaded.checkpoints, [checkpoint]);
    });

    test('resetAll clears everything, including the profile', () async {
      final state = await createState();
      await state.addWeightLog(100);
      await state.addPrediction(
        name: 'x',
        dailyCalories: 2000,
        activityLevel: ActivityLevel.sedentary,
      );
      await state.addCheckpoint('Trip', DateTime(2026, 12, 1));
      expect(state.hasAnyData, isTrue);

      await state.resetAll();
      expect(state.hasAnyData, isFalse);
      final reloaded = AppState(prefs);
      expect(reloaded.hasAnyData, isFalse);
      expect(reloaded.userProfile, isNull);
    });
  });

  group('units', () {
    test('kg <-> lbs conversions are exact inverses', () {
      expect(Units.kgToLbs(1), closeTo(2.20462262, 1e-8));
      expect(Units.lbsToKg(Units.kgToLbs(87.3)), closeTo(87.3, 1e-12));
    });

    test('differences agree with the rounded values shown', () {
      // 98.45 shows as 98.5 and 98.14 as 98.1, so the gap reads +0.4.
      expect(
        Units.formatDifference(98.45, 98.14, WeightUnit.kg, signed: true),
        '+0.4 kg',
      );
      expect(Units.format(98.45 - 98.14, WeightUnit.kg), '0.3 kg');
      expect(Units.formatDifference(80, 80.04, WeightUnit.kg), '0.0 kg');
      // Exact halves must round the same way in both helpers.
      expect(Units.format(99.25, WeightUnit.kg), '99.3 kg');
      expect(
        Units.formatDifference(98.46, 99.25, WeightUnit.kg, signed: true),
        '-0.8 kg',
      );
    });

    test('display helpers follow the preferred unit', () async {
      final state = await createState();
      expect(state.formatWeight(80), '80.0 kg');

      await state.setPreferredUnit(WeightUnit.lbs);
      expect(state.displayWeight(80), closeTo(176.37, 0.01));
      expect(state.formatWeight(80), '176.4 lbs');
      expect(state.formatWeight(-0.5, signed: true), '-1.1 lbs');
      expect(state.formatWeight(0.5, signed: true), '+1.1 lbs');
      expect(state.inputToKg(176.37), closeTo(80, 0.01));
      expect(AppState(prefs).unit, WeightUnit.lbs);
    });
  });

  group('archive', () {
    Future<AppState> withActive(int count) async {
      final state = await createState();
      await state.addWeightLog(100);
      for (var i = 0; i < count; i++) {
        now = now.add(const Duration(minutes: 1));
        await state.addPrediction(
          name: 'P$i',
          dailyCalories: 1500.0 + 100 * i,
          activityLevel: ActivityLevel.sedentary,
        );
      }
      return state;
    }

    test('caps the Arena at four, each in its own color slot', () async {
      final state = await withActive(AppState.maxActivePredictions);
      expect(state.hasRoomInArena, isFalse);
      expect(
        [for (final p in state.activePredictions) p.colorSlot],
        [0, 1, 2, 3],
      );
      expect(
        () => state.addPrediction(
          name: 'Fifth',
          dailyCalories: 2000,
          activityLevel: ActivityLevel.sedentary,
        ),
        throwsStateError,
      );
      expect(
        () => state.clonePrediction(state.predictions.first.id),
        throwsStateError,
      );

      final archived = await state.addPrediction(
        name: 'Fifth',
        dailyCalories: 2000,
        activityLevel: ActivityLevel.sedentary,
        archived: true,
      );
      expect(archived.isArchived, isTrue);
      expect(archived.colorSlot, isNull);
      expect(state.activePredictions, hasLength(4));
      expect(state.archivedPredictions, [archived]);
    });

    test('archiving frees a slot that the next one takes; others keep '
        'theirs', () async {
      final state = await withActive(4);
      final second = state.activePredictions[1];
      now = now.add(const Duration(days: 1));
      await state.archivePrediction(second.id);
      final archived = state.predictionById(second.id)!;
      expect(archived.archivedAt, now);
      expect(archived.colorSlot, isNull);
      expect([for (final p in state.activePredictions) p.colorSlot], [0, 2, 3]);

      final next = await state.addPrediction(
        name: 'New',
        dailyCalories: 2100,
        activityLevel: ActivityLevel.sedentary,
      );
      expect(next.colorSlot, 1);
      expect(() => state.unarchivePrediction(second.id), throwsStateError);

      await state.archivePrediction(state.activePredictions.first.id);
      await state.unarchivePrediction(second.id);
      expect(state.predictionById(second.id)!.isArchived, isFalse);
      expect(state.predictionById(second.id)!.colorSlot, 0);
    });

    test('ranking only counts the Arena; archived rank on their own', () async {
      final state = await withActive(2);
      final out = state.activePredictions.first;
      await state.archivePrediction(out.id);
      expect(state.evaluation!.byPosition.map((e) => e.predictionId), [
        state.activePredictions.single.id,
      ]);
      expect(state.evaluationFor(out.id), isNotNull);
      expect(state.archivedEvaluation!.byPosition.single.predictionId, out.id);
    });

    test('undo puts an active prediction in the archive if the Arena filled '
        'up meanwhile', () async {
      final state = await withActive(4);
      final victim = state.activePredictions.first;
      await state.deletePrediction(victim.id);
      await state.addPrediction(
        name: 'Filler',
        dailyCalories: 2500,
        activityLevel: ActivityLevel.sedentary,
      );
      await state.restorePrediction(victim, index: 0);
      final restored = state.predictionById(victim.id)!;
      expect(restored.isArchived, isTrue);
      expect(restored.colorSlot, isNull);
      expect(state.activePredictions, hasLength(4));
    });

    test('undo picks a free slot if its old one was taken', () async {
      final state = await withActive(2);
      final first = state.activePredictions.first; // slot 0
      await state.archivePrediction(first.id);
      final taker = await state.addPrediction(
        name: 'Taker',
        dailyCalories: 2500,
        activityLevel: ActivityLevel.sedentary,
      );
      expect(taker.colorSlot, 0);
      await state.restorePrediction(first);
      expect(state.predictionById(first.id)!.colorSlot, 2);
      expect(state.predictionById(first.id)!.isArchived, isFalse);
    });

    test('re-anchoring keeps the slot', () async {
      final state = await withActive(3);
      final p = state.activePredictions[2];
      final reanchored = await state.reanchorPrediction(p.id);
      expect(reanchored.colorSlot, p.colorSlot);
      expect(reanchored.isArchived, isFalse);
    });

    test('older saves load with the newest four active and the rest '
        'archived', () async {
      final legacy = [
        for (var i = 0; i < 6; i++)
          {
              ...PredictionSnapshot(
                id: 'p$i',
                name: 'P$i',
                createdAt: DateTime(2025, 12, 1 + i),
                startWeightKg: 100,
                dailyCalories: 2000,
                activityLevel: ActivityLevel.sedentary,
                points: const [],
              ).toJson(),
            }
            ..remove('colorSlot')
            ..remove('archivedAt'),
      ];
      SharedPreferences.setMockInitialValues({
        'losertown.v1.predictions': jsonEncode(legacy),
      });
      prefs = await SharedPreferences.getInstance();
      final state = AppState(prefs, clock: () => now);

      expect(
        [for (final p in state.activePredictions) p.id],
        ['p2', 'p3', 'p4', 'p5'],
      );
      expect(
        [for (final p in state.activePredictions) p.colorSlot],
        [0, 1, 2, 3],
      );
      expect([
        for (final p in state.archivedPredictions) p.id,
      ], unorderedEquals(['p0', 'p1']));
      // The repair is saved, so it doesn't re-run with a new date.
      final reloaded = AppState(
        prefs,
        clock: () => now.add(const Duration(days: 9)),
      );
      expect(reloaded.predictions, state.predictions);
    });
  });
}
