import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/services/losertown_math.dart';

/// Encodes to a JSON string and back, as persistence does.
Map<String, dynamic> roundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  test('UserProfile round-trips with wire values', () {
    const profile = UserProfile(
      heightCm: 172.5,
      age: 41,
      sex: Sex.female,
      preferredUnit: WeightUnit.lbs,
    );
    final json = roundTrip(profile.toJson());
    expect(json['sex'], 'female');
    expect(json['preferredUnit'], 'lbs');
    expect(UserProfile.fromJson(json), profile);
  });

  test('PredictionSnapshot round-trips including points', () {
    final points = LosertownMath.generateProjection(
      profile: const UserProfile(heightCm: 180, age: 30, sex: Sex.male),
      startWeightKg: 95,
      dailyCalories: 2100,
      activityLevel: ActivityLevel.lightlyActive,
      startDate: DateTime(2026, 3, 1),
      weeks: 60,
    );
    final snapshot = PredictionSnapshot(
      id: 'abc',
      name: 'Cut',
      createdAt: DateTime(2026, 3, 1, 9, 15),
      startWeightKg: 95,
      dailyCalories: 2100,
      activityLevel: ActivityLevel.lightlyActive,
      targetWeightKg: 85,
      points: points,
    );
    final json = roundTrip(snapshot.toJson());
    expect(json['activityLevel'], 'lightlyActive');
    expect(PredictionSnapshot.fromJson(json), snapshot);
  });

  test('nullable target survives round-trip', () {
    final snapshot = PredictionSnapshot(
      id: 'n',
      name: 'n',
      createdAt: DateTime(2026),
      startWeightKg: 80,
      dailyCalories: 1800,
      activityLevel: ActivityLevel.sedentary,
      points: const [],
    );
    expect(PredictionSnapshot.fromJson(roundTrip(snapshot.toJson())), snapshot);
  });

  test('WeightLog round-trips', () {
    final log = WeightLog(
      id: 'l1',
      date: DateTime(2026, 5, 2, 7),
      weightKg: 81.3,
    );
    expect(WeightLog.fromJson(roundTrip(log.toJson())), log);
  });

  test('PredictionEvaluation round-trips with snake_case status', () {
    const eval = PredictionEvaluation(
      predictionId: 'p',
      expectedWeightTodayKg: 90.2,
      deltaFromActualKg: -1.4,
      adherenceStatus: AdherenceStatus.offCourse,
      expectedWeeklyRateKg: -0.6,
      paceDeltaKg: 0.1,
    );
    final json = roundTrip(eval.toJson());
    expect(json['adherenceStatus'], 'off_course');
    final back = PredictionEvaluation.fromJson(json);
    expect(back.adherenceStatus, AdherenceStatus.offCourse);
    expect(back.paceDeltaKg, 0.1);
    expect(back.impliedDailyCalories, isNull);
  });

  test('unknown enum values fail loudly', () {
    expect(() => Sex.fromWire('other'), throwsFormatException);
    expect(() => ActivityLevel.fromWire('couch'), throwsFormatException);
  });

  test('prediction snapshot round-trips archive fields, tolerating old '
      'saves without them', () {
    final p = PredictionSnapshot(
      id: 'p',
      name: 'Cut',
      createdAt: DateTime(2026, 1, 1),
      startWeightKg: 90,
      dailyCalories: 1800,
      activityLevel: ActivityLevel.sedentary,
      points: const [],
      archivedAt: DateTime(2026, 2, 1),
    );
    final back = PredictionSnapshot.fromJson(roundTrip(p.toJson()));
    expect(back, p);
    expect(back.isArchived, isTrue);

    final active = p.copyWith(colorSlot: () => 2, archivedAt: () => null);
    final old = roundTrip(active.toJson())
      ..remove('colorSlot')
      ..remove('archivedAt');
    final legacy = PredictionSnapshot.fromJson(old);
    expect(legacy.isArchived, isFalse);
    expect(legacy.colorSlot, isNull);
    expect(PredictionSnapshot.fromJson(roundTrip(active.toJson())), active);
  });
}
