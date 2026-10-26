import 'package:flutter/foundation.dart';

/// Biological sex, used only by the Mifflin-St Jeor BMR constant.
enum Sex {
  male('male'),
  female('female');

  const Sex(this.wireValue);
  final String wireValue;

  static Sex fromWire(String value) => Sex.values.firstWhere(
    (s) => s.wireValue == value,
    orElse: () => throw FormatException('Unknown sex: $value'),
  );
}

/// Display unit preference. All internal math and storage is in kilograms.
enum WeightUnit {
  kg('kg'),
  lbs('lbs');

  const WeightUnit(this.wireValue);
  final String wireValue;

  static WeightUnit fromWire(String value) => WeightUnit.values.firstWhere(
    (u) => u.wireValue == value,
    orElse: () => throw FormatException('Unknown unit: $value'),
  );
}

/// Standard TDEE activity multipliers applied on top of BMR.
enum ActivityLevel {
  sedentary(1.2),
  lightlyActive(1.375),
  moderatelyActive(1.55),
  veryActive(1.725),
  extraActive(1.9);

  const ActivityLevel(this.multiplier);
  final double multiplier;

  static ActivityLevel fromWire(String value) =>
      ActivityLevel.values.firstWhere(
        (a) => a.name == value,
        orElse: () => throw FormatException('Unknown activity level: $value'),
      );
}

/// How closely the user's actual weight tracks a saved prediction.
enum AdherenceStatus {
  onTrack('on_track'),
  drifting('drifting'),
  offCourse('off_course');

  const AdherenceStatus(this.wireValue);
  final String wireValue;

  static AdherenceStatus fromWire(String value) =>
      AdherenceStatus.values.firstWhere(
        (s) => s.wireValue == value,
        orElse: () => throw FormatException('Unknown status: $value'),
      );
}

@immutable
class UserProfile {
  const UserProfile({
    required this.heightCm,
    required this.age,
    required this.sex,
    this.preferredUnit = WeightUnit.kg,
  });

  final double heightCm;
  final int age;
  final Sex sex;
  final WeightUnit preferredUnit;

  UserProfile copyWith({
    double? heightCm,
    int? age,
    Sex? sex,
    WeightUnit? preferredUnit,
  }) => UserProfile(
    heightCm: heightCm ?? this.heightCm,
    age: age ?? this.age,
    sex: sex ?? this.sex,
    preferredUnit: preferredUnit ?? this.preferredUnit,
  );

  Map<String, dynamic> toJson() => {
    'heightCm': heightCm,
    'age': age,
    'sex': sex.wireValue,
    'preferredUnit': preferredUnit.wireValue,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    heightCm: (json['heightCm'] as num).toDouble(),
    age: (json['age'] as num).toInt(),
    sex: Sex.fromWire(json['sex'] as String),
    preferredUnit: WeightUnit.fromWire(json['preferredUnit'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.heightCm == heightCm &&
      other.age == age &&
      other.sex == sex &&
      other.preferredUnit == preferredUnit;

  @override
  int get hashCode => Object.hash(heightCm, age, sex, preferredUnit);
}

/// One week of a projection. Week 0 is the starting anchor.
///
/// [dynamicTdee] is the TDEE at this point's [projectedWeightKg]; it drives
/// the energy balance of the *following* week. [weeklyChangeKg] is the change
/// over the week that ended at this point (negative = loss).
@immutable
class WeeklyProjectionPoint {
  const WeeklyProjectionPoint({
    required this.weekNumber,
    required this.date,
    required this.projectedWeightKg,
    required this.weeklyChangeKg,
    required this.dynamicTdee,
  });

  final int weekNumber;
  final DateTime date;
  final double projectedWeightKg;
  final double weeklyChangeKg;
  final double dynamicTdee;

  Map<String, dynamic> toJson() => {
    'weekNumber': weekNumber,
    'date': date.toIso8601String(),
    'projectedWeightKg': projectedWeightKg,
    'weeklyChangeKg': weeklyChangeKg,
    'dynamicTdee': dynamicTdee,
  };

  factory WeeklyProjectionPoint.fromJson(Map<String, dynamic> json) =>
      WeeklyProjectionPoint(
        weekNumber: (json['weekNumber'] as num).toInt(),
        date: DateTime.parse(json['date'] as String),
        projectedWeightKg: (json['projectedWeightKg'] as num).toDouble(),
        weeklyChangeKg: (json['weeklyChangeKg'] as num).toDouble(),
        dynamicTdee: (json['dynamicTdee'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is WeeklyProjectionPoint &&
      other.weekNumber == weekNumber &&
      other.date == date &&
      other.projectedWeightKg == projectedWeightKg &&
      other.weeklyChangeKg == weeklyChangeKg &&
      other.dynamicTdee == dynamicTdee;

  @override
  int get hashCode => Object.hash(
    weekNumber,
    date,
    projectedWeightKg,
    weeklyChangeKg,
    dynamicTdee,
  );
}

/// A saved projection. [createdAt] is the anchor date of week 0.
@immutable
class PredictionSnapshot {
  PredictionSnapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.startWeightKg,
    required this.dailyCalories,
    required this.activityLevel,
    this.targetWeightKg,
    required List<WeeklyProjectionPoint> points,
    this.colorSlot,
    this.archivedAt,
  }) : points = List.unmodifiable(points);

  final String id;
  final String name;
  final DateTime createdAt;
  final double startWeightKg;
  final double dailyCalories;
  final ActivityLevel activityLevel;
  final double? targetWeightKg;
  final List<WeeklyProjectionPoint> points;

  /// The chart color/dash slot this prediction holds while it's active, so
  /// its line keeps one look however others come and go. Null when archived.
  final int? colorSlot;

  /// When it was moved out of the Arena; null while active.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// Number of projected weeks, excluding the week-0 anchor.
  int get horizonWeeks => points.isEmpty ? 0 : points.length - 1;

  PredictionSnapshot copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    double? startWeightKg,
    double? dailyCalories,
    ActivityLevel? activityLevel,
    double? Function()? targetWeightKg,
    List<WeeklyProjectionPoint>? points,
    int? Function()? colorSlot,
    DateTime? Function()? archivedAt,
  }) => PredictionSnapshot(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    startWeightKg: startWeightKg ?? this.startWeightKg,
    dailyCalories: dailyCalories ?? this.dailyCalories,
    activityLevel: activityLevel ?? this.activityLevel,
    targetWeightKg: targetWeightKg != null
        ? targetWeightKg()
        : this.targetWeightKg,
    points: points ?? this.points,
    colorSlot: colorSlot != null ? colorSlot() : this.colorSlot,
    archivedAt: archivedAt != null ? archivedAt() : this.archivedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'startWeightKg': startWeightKg,
    'dailyCalories': dailyCalories,
    'activityLevel': activityLevel.name,
    'targetWeightKg': targetWeightKg,
    'points': points.map((p) => p.toJson()).toList(),
    'colorSlot': colorSlot,
    'archivedAt': archivedAt?.toIso8601String(),
  };

  factory PredictionSnapshot.fromJson(Map<String, dynamic> json) =>
      PredictionSnapshot(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        startWeightKg: (json['startWeightKg'] as num).toDouble(),
        dailyCalories: (json['dailyCalories'] as num).toDouble(),
        activityLevel: ActivityLevel.fromWire(json['activityLevel'] as String),
        targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
        points: (json['points'] as List)
            .map(
              (p) => WeeklyProjectionPoint.fromJson(p as Map<String, dynamic>),
            )
            .toList(),
        colorSlot: json['colorSlot'] as int?,
        archivedAt: switch (json['archivedAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is PredictionSnapshot &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.startWeightKg == startWeightKg &&
      other.dailyCalories == dailyCalories &&
      other.activityLevel == activityLevel &&
      other.targetWeightKg == targetWeightKg &&
      other.colorSlot == colorSlot &&
      other.archivedAt == archivedAt &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    startWeightKg,
    dailyCalories,
    activityLevel,
    targetWeightKg,
    colorSlot,
    archivedAt,
    Object.hashAll(points),
  );
}

@immutable
class WeightLog {
  const WeightLog({
    required this.id,
    required this.date,
    required this.weightKg,
  });

  final String id;
  final DateTime date;
  final double weightKg;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'weightKg': weightKg,
  };

  factory WeightLog.fromJson(Map<String, dynamic> json) => WeightLog(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    weightKg: (json['weightKg'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is WeightLog &&
      other.id == id &&
      other.date == date &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(id, date, weightKg);
}

/// One calendar day of weigh-ins after EMA smoothing.
@immutable
class SmoothedWeight {
  const SmoothedWeight({
    required this.date,
    required this.rawWeightKg,
    required this.smoothedWeightKg,
  });

  /// Calendar day (local midnight).
  final DateTime date;

  /// Mean of all weigh-ins logged on [date].
  final double rawWeightKg;
  final double smoothedWeightKg;
}

/// How one saved prediction compares with the user's actual trend.
///
/// Sign conventions: rates are change per week (negative = losing), and
/// deltas are `actual - expected` (positive = heavier / slower than planned).
@immutable
class PredictionEvaluation {
  const PredictionEvaluation({
    required this.predictionId,
    required this.expectedWeightTodayKg,
    required this.deltaFromActualKg,
    required this.adherenceStatus,
    required this.expectedWeeklyRateKg,
    this.paceDeltaKg,
    this.impliedDailyCalories,
  });

  final String predictionId;
  final double expectedWeightTodayKg;
  final double deltaFromActualKg;
  final AdherenceStatus adherenceStatus;
  final double expectedWeeklyRateKg;

  /// Null when there isn't enough recent data to measure the user's pace.
  final double? paceDeltaKg;

  /// Daily intake that explains the user's actual pace, assuming this
  /// prediction's activity level. Null when pace is unknown.
  final double? impliedDailyCalories;

  Map<String, dynamic> toJson() => {
    'predictionId': predictionId,
    'expectedWeightTodayKg': expectedWeightTodayKg,
    'deltaFromActualKg': deltaFromActualKg,
    'adherenceStatus': adherenceStatus.wireValue,
    'expectedWeeklyRateKg': expectedWeeklyRateKg,
    'paceDeltaKg': paceDeltaKg,
    'impliedDailyCalories': impliedDailyCalories,
  };

  factory PredictionEvaluation.fromJson(
    Map<String, dynamic> json,
  ) => PredictionEvaluation(
    predictionId: json['predictionId'] as String,
    expectedWeightTodayKg: (json['expectedWeightTodayKg'] as num).toDouble(),
    deltaFromActualKg: (json['deltaFromActualKg'] as num).toDouble(),
    adherenceStatus: AdherenceStatus.fromWire(
      json['adherenceStatus'] as String,
    ),
    expectedWeeklyRateKg: (json['expectedWeeklyRateKg'] as num).toDouble(),
    paceDeltaKg: (json['paceDeltaKg'] as num?)?.toDouble(),
    impliedDailyCalories: (json['impliedDailyCalories'] as num?)?.toDouble(),
  );
}

/// Result of matching all saved predictions against the weight log.
@immutable
class PredictionMatchResult {
  PredictionMatchResult({
    required this.asOf,
    required this.currentWeightKg,
    required this.actualWeeklyRateKg,
    required List<PredictionEvaluation> byPosition,
    required List<PredictionEvaluation> byPace,
  }) : byPosition = List.unmodifiable(byPosition),
       byPace = List.unmodifiable(byPace);

  /// Day the comparison is made for: the most recent weigh-in.
  final DateTime asOf;

  /// EMA-smoothed weight on [asOf].
  final double currentWeightKg;

  /// Slope of the smoothed weight over the trailing window, per week.
  final double? actualWeeklyRateKg;

  /// All predictions, closest expected weight first.
  final List<PredictionEvaluation> byPosition;

  /// Predictions closest in weekly pace first. Empty when pace is unknown.
  final List<PredictionEvaluation> byPace;
}

/// A user-pinned goal date, e.g. "Beach Trip" on Dec 15.
@immutable
class Checkpoint {
  const Checkpoint({required this.id, required this.label, required this.date});

  final String id;
  final String label;

  /// Calendar day (local midnight).
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'date': date.toIso8601String(),
  };

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
    id: json['id'] as String,
    label: json['label'] as String,
    date: DateTime.parse(json['date'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is Checkpoint &&
      other.id == id &&
      other.label == label &&
      other.date == date;

  @override
  int get hashCode => Object.hash(id, label, date);
}
