import '../models/app_models.dart';
import '../utils/units.dart';

enum MilestoneKind {
  /// Crossed a round number (every 5 kg or 10 lbs).
  mark,

  /// Reached the target weight.
  target,
}

class ProjectionMilestone {
  const ProjectionMilestone({
    required this.kind,
    required this.weightKg,
    required this.losing,
  });

  final MilestoneKind kind;

  /// The mark or target that was reached, in kg.
  final double weightKg;

  /// Whether the mark was crossed on the way down.
  final bool losing;
}

/// Display-unit spacing between round-number milestones.
double milestoneStep(WeightUnit unit) => switch (unit) {
  WeightUnit.kg => 5,
  WeightUnit.lbs => 10,
};

/// One entry per projection point (null where nothing notable happens).
///
/// A week is a milestone if it reaches the target, or if the projected weight
/// crosses a multiple of [milestoneStep] in the display [unit]. When a week
/// crosses several marks, the one closest to the new weight is reported.
List<ProjectionMilestone?> findMilestones(
  List<WeeklyProjectionPoint> points, {
  required WeightUnit unit,
  double? targetWeightKg,
}) {
  const epsilon = 1e-9;
  final step = milestoneStep(unit);
  final result = List<ProjectionMilestone?>.filled(points.length, null);

  for (var i = 1; i < points.length; i++) {
    final prevKg = points[i - 1].projectedWeightKg;
    final currKg = points[i].projectedWeightKg;
    if (currKg == prevKg) continue;
    final losing = currKg < prevKg;

    if (targetWeightKg != null && currKg == targetWeightKg) {
      result[i] = ProjectionMilestone(
        kind: MilestoneKind.target,
        weightKg: targetWeightKg,
        losing: losing,
      );
      continue;
    }

    final prev = Units.fromKg(prevKg, unit);
    final curr = Units.fromKg(currKg, unit);
    final mark = losing
        ? (curr / step - epsilon).ceil() * step
        : (curr / step + epsilon).floor() * step;
    final crossed = losing ? mark < prev - epsilon : mark > prev + epsilon;
    if (crossed) {
      result[i] = ProjectionMilestone(
        kind: MilestoneKind.mark,
        weightKg: Units.toKg(mark, unit),
        losing: losing,
      );
    }
  }
  return result;
}
