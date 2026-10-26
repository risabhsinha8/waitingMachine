import 'dart:async';

import 'package:flutter/services.dart';

/// The app's haptic vocabulary, kept subtle and consistent.
///
/// Fire-and-forget: haptics must never delay the UI response they accompany,
/// and platforms without them (some desktops) must not surface errors.
abstract final class Haptics {
  /// A slider crossed a round number.
  static void tick() => _fire(HapticFeedback.selectionClick());

  /// Something was saved: a weigh-in, a prediction, a checkpoint.
  static void saved() => _fire(HapticFeedback.mediumImpact());

  /// Something was deleted.
  static void deleted() => _fire(HapticFeedback.lightImpact());

  static void _fire(Future<void> haptic) =>
      unawaited(haptic.catchError((Object _) {}));

  /// Ticks when a slider moves from [from] to [to] across a multiple of
  /// [step] (e.g. every 100 kcal).
  static void tickOnStepCross(double from, double to, double step) {
    if ((from / step).floor() != (to / step).floor()) tick();
  }
}
