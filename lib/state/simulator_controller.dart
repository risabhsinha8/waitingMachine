import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../services/losertown_math.dart';
import '../services/projection_milestones.dart';
import 'app_state.dart';

/// Inputs and live projection for the Simulator tab.
///
/// Recomputes synchronously on every input change; a 52-104 week projection
/// is a few hundred floating-point operations, well inside a frame.
class SimulatorController extends ChangeNotifier {
  SimulatorController(this._app, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _startWeightKg = _app.latestLoggedWeightKg ?? defaultStartWeightKg;
    _syncedLatestKg = _app.latestLoggedWeightKg;
    _profile = _app.userProfile;
    _unit = _app.unit;
    _app.addListener(_onAppChanged);
    _recompute();
  }

  static const double defaultStartWeightKg = 80;
  static const double defaultDailyCalories = 2000;
  static const double minWeightKg = 35;
  static const double maxWeightKg = 250;
  static const double minCalories = 1000;
  static const double maxCalories = 4500;
  static const double calorieStep = 10;

  final AppState _app;
  final DateTime Function() _clock;

  late double _startWeightKg;
  double _dailyCalories = defaultDailyCalories;
  ActivityLevel _activityLevel = ActivityLevel.lightlyActive;
  double? _targetWeightKg;
  int _weeks = LosertownMath.minProjectionWeeks;
  PredictionSnapshot? _loadedFrom;
  int _loadGeneration = 0;

  /// Once the user picks a start weight, new weigh-ins stop overriding it.
  bool _startWeightEdited = false;
  double? _syncedLatestKg;
  UserProfile? _profile;
  WeightUnit _unit = WeightUnit.kg;

  List<WeeklyProjectionPoint> _points = const [];
  List<ProjectionMilestone?> _milestones = const [];

  double get startWeightKg => _startWeightKg;
  double get dailyCalories => _dailyCalories;
  ActivityLevel get activityLevel => _activityLevel;
  double? get targetWeightKg => _targetWeightKg;
  int get weeks => _weeks;
  UserProfile? get profile => _profile;
  WeightUnit get unit => _unit;

  /// The saved prediction the current inputs were loaded from, if any.
  PredictionSnapshot? get loadedFrom => _loadedFrom;

  /// Increments on every [loadPrediction], including reloading the same one,
  /// so views can react to each load.
  int get loadGeneration => _loadGeneration;

  /// Empty until a profile exists.
  List<WeeklyProjectionPoint> get points => _points;

  /// Parallel to [points].
  List<ProjectionMilestone?> get milestones => _milestones;

  /// First week at the target weight, or null if not reached in the horizon.
  WeeklyProjectionPoint? get targetReachedAt {
    for (var i = 0; i < _points.length; i++) {
      if (_milestones[i]?.kind == MilestoneKind.target) return _points[i];
    }
    return null;
  }

  void setStartWeight(double kg) {
    _startWeightEdited = true;
    _update(() => _startWeightKg = kg.clamp(minWeightKg, maxWeightKg));
  }

  void setDailyCalories(double kcal) =>
      _update(() => _dailyCalories = kcal.clamp(minCalories, maxCalories));

  void setActivityLevel(ActivityLevel level) =>
      _update(() => _activityLevel = level);

  void setTargetWeight(double? kg) =>
      _update(() => _targetWeightKg = kg?.clamp(minWeightKg, maxWeightKg));

  /// Copies a saved prediction's inputs in, to tweak and lock in as new.
  void loadPrediction(PredictionSnapshot prediction) {
    _startWeightEdited = true;
    _update(() {
      _startWeightKg = prediction.startWeightKg;
      _dailyCalories = prediction.dailyCalories;
      _activityLevel = prediction.activityLevel;
      _targetWeightKg = prediction.targetWeightKg;
      _weeks = prediction.horizonWeeks.clamp(
        LosertownMath.minProjectionWeeks,
        LosertownMath.maxProjectionWeeks,
      );
      _loadedFrom = prediction;
      _loadGeneration++;
    });
  }

  void clearLoadedPrediction() => _update(() => _loadedFrom = null);

  void _update(VoidCallback change) {
    change();
    _recompute();
    notifyListeners();
  }

  void _onAppChanged() {
    var changed = false;
    final latest = _app.latestLoggedWeightKg;
    if (latest != _syncedLatestKg) {
      _syncedLatestKg = latest;
      if (!_startWeightEdited && latest != null) {
        _startWeightKg = latest.clamp(minWeightKg, maxWeightKg);
        changed = true;
      }
    }
    if (_app.userProfile != _profile || _app.unit != _unit) {
      _profile = _app.userProfile;
      _unit = _app.unit;
      changed = true;
    }
    if (_loadedFrom != null && _app.predictionById(_loadedFrom!.id) == null) {
      _loadedFrom = null;
      changed = true;
    }
    if (changed) {
      _recompute();
      notifyListeners();
    }
  }

  void _recompute() {
    final profile = _profile;
    if (profile == null) {
      _points = const [];
      _milestones = const [];
      return;
    }
    _points = LosertownMath.generateProjection(
      profile: profile,
      startWeightKg: _startWeightKg,
      dailyCalories: _dailyCalories,
      activityLevel: _activityLevel,
      startDate: _clock(),
      weeks: _weeks,
      targetWeightKg: _targetWeightKg,
    );
    _milestones = findMilestones(
      _points,
      unit: _unit,
      targetWeightKg: _targetWeightKg,
    );
  }

  @override
  void dispose() {
    _app.removeListener(_onAppChanged);
    super.dispose();
  }
}
