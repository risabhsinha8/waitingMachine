import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../utils/units.dart';

extension ActivityLevelLabels on ActivityLevel {
  String get label => switch (this) {
    ActivityLevel.sedentary => 'Sedentary',
    ActivityLevel.lightlyActive => 'Light',
    ActivityLevel.moderatelyActive => 'Moderate',
    ActivityLevel.veryActive => 'Very active',
    ActivityLevel.extraActive => 'Extra active',
  };

  /// Full name for badges, e.g. "Lightly Active".
  String get longLabel => switch (this) {
    ActivityLevel.sedentary => 'Sedentary',
    ActivityLevel.lightlyActive => 'Lightly Active',
    ActivityLevel.moderatelyActive => 'Moderately Active',
    ActivityLevel.veryActive => 'Very Active',
    ActivityLevel.extraActive => 'Extra Active',
  };

  String get description => switch (this) {
    ActivityLevel.sedentary => 'Desk job, little or no exercise',
    ActivityLevel.lightlyActive => 'Light exercise 1-3 days a week',
    ActivityLevel.moderatelyActive => 'Moderate exercise 3-5 days a week',
    ActivityLevel.veryActive => 'Hard exercise 6-7 days a week',
    ActivityLevel.extraActive => 'Physical job plus hard training',
  };
}

extension AdherenceStatusLabels on AdherenceStatus {
  String get label => switch (this) {
    AdherenceStatus.onTrack => 'Sticking To It',
    AdherenceStatus.drifting => 'Drifting',
    AdherenceStatus.offCourse => 'Off Course',
  };
}

extension SexLabels on Sex {
  String get label => switch (this) {
    Sex.male => 'Male',
    Sex.female => 'Female',
  };
}

const double cmPerInch = 2.54;

/// `180 cm`, or `5′11″` for imperial users.
String formatHeight(double cm, WeightUnit unit) {
  if (unit == WeightUnit.kg) return '${cm.round()} cm';
  final totalInches = (cm / cmPerInch).round();
  return '${totalInches ~/ 12}′${totalInches % 12}″';
}

final NumberFormat _integer = NumberFormat.decimalPattern();

/// `1,850 kcal`; [signed] prefixes positive values with `+`.
String formatKcal(double kcal, {bool signed = false}) {
  final rounded = kcal.round();
  final sign = signed && rounded > 0 ? '+' : (rounded < 0 ? '−' : '');
  return '$sign${_integer.format(rounded.abs())} kcal';
}

final DateFormat projectionDate = DateFormat('MMM d, yyyy');

final DateFormat shortDate = DateFormat('MMM d');

/// `1,650 kcal/day • Lightly Active`, plus the target if there is one.
String rulesLabel(PredictionSnapshot p, WeightUnit unit) => [
  '${formatKcal(p.dailyCalories)}/day',
  p.activityLevel.longLabel,
  if (p.targetWeightKg != null)
    'Target ${Units.format(p.targetWeightKg!, unit)}',
].join(' • ');
