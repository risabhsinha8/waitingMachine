import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/app_models.dart';

/// kg <-> lbs conversion for display. Storage and math always use kg.
abstract final class Units {
  /// Exact, by international definition.
  static const double kgPerLb = 0.45359237;

  static double kgToLbs(double kg) => kg / kgPerLb;
  static double lbsToKg(double lbs) => lbs * kgPerLb;

  /// Converts a stored kg value into [unit] for display.
  static double fromKg(double kg, WeightUnit unit) => switch (unit) {
    WeightUnit.kg => kg,
    WeightUnit.lbs => kgToLbs(kg),
  };

  /// Converts a user-entered value in [unit] into kg for storage.
  static double toKg(double value, WeightUnit unit) => switch (unit) {
    WeightUnit.kg => value,
    WeightUnit.lbs => lbsToKg(value),
  };

  /// e.g. `82.4 kg`, `181.7 lbs`, or `-0.5 kg` with [signed] for deltas.
  static String format(
    double kg,
    WeightUnit unit, {
    int decimals = 1,
    bool signed = false,
  }) {
    // Round first, so NumberFormat (which rounds half-to-even) never
    // disagrees with [formatDifference].
    final value = _round(fromKg(kg, unit), decimals);
    final number = NumberFormat.decimalPatternDigits(
      decimalDigits: decimals,
    ).format(value);
    final sign = signed && value > 0 ? '+' : '';
    return '$sign$number ${unit.wireValue}';
  }

  /// Formats `aKg - bKg` as the difference of the two values *as displayed*,
  /// so "98.5 kg" next to "98.1 kg" reads as +0.4, not an unrounded +0.3.
  static String formatDifference(
    double aKg,
    double bKg,
    WeightUnit unit, {
    int decimals = 1,
    bool signed = false,
  }) {
    final difference =
        _round(fromKg(aKg, unit), decimals) -
        _round(fromKg(bKg, unit), decimals);
    return format(
      toKg(difference, unit),
      unit,
      decimals: decimals,
      signed: signed,
    );
  }

  /// Rounds half away from zero to [decimals] places.
  static double _round(double value, int decimals) {
    final scale = math.pow(10, decimals);
    return (value * scale).round() / scale;
  }
}
