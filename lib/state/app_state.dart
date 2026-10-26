import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_models.dart';
import '../services/losertown_math.dart';
import '../utils/units.dart';

/// App-wide state: profile, saved predictions, and weight logs, persisted to
/// [SharedPreferences] as JSON.
class AppState extends ChangeNotifier {
  AppState(this._prefs, {DateTime Function()? clock, Uuid uuid = const Uuid()})
    : _clock = clock ?? DateTime.now,
      _uuid = uuid {
    _restore();
  }

  /// Loads the shared preferences instance and restores saved state.
  static Future<AppState> load({DateTime Function()? clock}) async =>
      AppState(await SharedPreferences.getInstance(), clock: clock);

  static const _profileKey = 'losertown.v1.profile';
  static const _predictionsKey = 'losertown.v1.predictions';
  static const _weightLogsKey = 'losertown.v1.weightLogs';
  static const _checkpointsKey = 'losertown.v1.checkpoints';

  /// Most checkpoints a user can pin at once.
  static const int maxCheckpoints = 3;

  /// Most predictions competing in the Arena at once. Past this the chart
  /// stops being readable and the closest match stops meaning much, so the
  /// rest live in the archive, which has no limit.
  static const int maxActivePredictions = 4;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final Uuid _uuid;

  UserProfile? _userProfile;
  List<PredictionSnapshot> _predictions = const [];
  List<WeightLog> _weightLogs = const [];
  List<Checkpoint> _checkpoints = const [];

  /// The app's notion of "now"; injectable so UI and tests agree on today.
  DateTime now() => _clock();

  UserProfile? get userProfile => _userProfile;

  /// Active and archived, in creation order.
  List<PredictionSnapshot> get predictions => _predictions;

  /// The predictions in the Arena, in creation order.
  List<PredictionSnapshot> get activePredictions => [
    for (final p in _predictions)
      if (!p.isArchived) p,
  ];

  /// Most recently archived first.
  List<PredictionSnapshot> get archivedPredictions => [
    for (final p in _predictions)
      if (p.isArchived) p,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));

  bool get hasRoomInArena => activePredictions.length < maxActivePredictions;

  /// Sorted oldest first.
  List<WeightLog> get weightLogs => _weightLogs;

  /// Sorted by date.
  List<Checkpoint> get checkpoints => _checkpoints;

  bool get hasAnyData =>
      _userProfile != null ||
      _predictions.isNotEmpty ||
      _weightLogs.isNotEmpty ||
      _checkpoints.isNotEmpty;

  WeightUnit get unit => _userProfile?.preferredUnit ?? WeightUnit.kg;

  /// Most recent raw weigh-in, or null with no logs.
  double? get latestLoggedWeightKg =>
      _weightLogs.isEmpty ? null : _weightLogs.last.weightKg;

  List<SmoothedWeight> get smoothedWeights =>
      LosertownMath.smoothWeights(_weightLogs);

  /// Latest EMA-smoothed weight, or null with no logs.
  double? get currentWeightKg {
    final smoothed = smoothedWeights;
    return smoothed.isEmpty ? null : smoothed.last.smoothedWeightKg;
  }

  /// How the Arena's predictions rank against reality.
  PredictionMatchResult? get evaluation => LosertownMath.evaluatePredictions(
    activePredictions,
    _weightLogs,
    unit: unit,
  );

  /// Archived predictions against reality, ranked among themselves only.
  PredictionMatchResult? get archivedEvaluation =>
      LosertownMath.evaluatePredictions(
        archivedPredictions,
        _weightLogs,
        unit: unit,
      );

  /// How one prediction compares with reality, or null without weigh-ins.
  PredictionEvaluation? evaluationFor(String predictionId) {
    final archived = predictionById(predictionId)?.isArchived ?? false;
    final result = archived ? archivedEvaluation : evaluation;
    for (final e in result?.byPosition ?? const <PredictionEvaluation>[]) {
      if (e.predictionId == predictionId) return e;
    }
    return null;
  }

  PredictionSnapshot? predictionById(String id) {
    for (final p in _predictions) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Future<void> setUserProfile(UserProfile profile) async {
    _userProfile = profile;
    notifyListeners();
    await _prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<void> setPreferredUnit(WeightUnit unit) =>
      setUserProfile(_requireProfile().copyWith(preferredUnit: unit));

  // ---------------------------------------------------------------------------
  // Predictions
  // ---------------------------------------------------------------------------

  /// Creates and saves a projection starting today. [startWeightKg] defaults
  /// to the current smoothed weight. It joins the Arena unless [archived];
  /// throws [StateError] if the Arena is full.
  Future<PredictionSnapshot> addPrediction({
    required String name,
    required double dailyCalories,
    required ActivityLevel activityLevel,
    double? startWeightKg,
    double? targetWeightKg,
    int weeks = LosertownMath.minProjectionWeeks,
    bool archived = false,
  }) async {
    final snapshot = _placed(
      _buildSnapshot(
        id: _uuid.v4(),
        name: name,
        startWeightKg: startWeightKg ?? _requireCurrentWeight(),
        dailyCalories: dailyCalories,
        activityLevel: activityLevel,
        targetWeightKg: targetWeightKg,
        weeks: weeks,
      ),
      active: !archived,
    );
    _predictions = [..._predictions, snapshot];
    notifyListeners();
    await _savePredictions();
    return snapshot;
  }

  Future<void> deletePrediction(String id) async {
    _predictions = [
      for (final p in _predictions)
        if (p.id != id) p,
    ];
    notifyListeners();
    await _savePredictions();
  }

  Future<void> renamePrediction(String id, String name) =>
      _replacePrediction(_requirePrediction(id).copyWith(name: name));

  /// Moves a prediction out of the Arena, keeping its history.
  Future<void> archivePrediction(String id) async {
    final p = _requirePrediction(id);
    if (p.isArchived) return;
    await _replacePrediction(_placed(p, active: false));
  }

  /// Brings an archived prediction back into the Arena; throws [StateError]
  /// if the Arena is full.
  Future<void> unarchivePrediction(String id) async {
    final p = _requirePrediction(id);
    if (!p.isArchived) return;
    await _replacePrediction(_placed(p, active: true));
  }

  /// Puts back a prediction removed or changed earlier, e.g. for Undo.
  /// Replaces the prediction with the same id if present, otherwise inserts
  /// it at [index] (clamped), or at the end. An active one lands in the
  /// archive if the Arena has filled up since, and takes a free color slot
  /// if its old one has been taken.
  Future<void> restorePrediction(
    PredictionSnapshot snapshot, {
    int? index,
  }) async {
    final others = [
      for (final p in _predictions)
        if (p.id != snapshot.id) p,
    ];
    final fitted = snapshot.isArchived
        ? snapshot
        : _fitted(snapshot, [
            for (final p in others)
              if (!p.isArchived) p,
          ]);
    if (predictionById(snapshot.id) != null) {
      return _replacePrediction(fitted);
    }
    final at = (index ?? _predictions.length).clamp(0, _predictions.length);
    _predictions = [..._predictions]..insert(at, fitted);
    notifyListeners();
    await _savePredictions();
  }

  PredictionSnapshot _fitted(
    PredictionSnapshot snapshot,
    List<PredictionSnapshot> active,
  ) {
    if (active.length >= maxActivePredictions) {
      return snapshot.copyWith(colorSlot: () => null, archivedAt: _clock);
    }
    final taken = active.any((p) => p.colorSlot == snapshot.colorSlot);
    if (snapshot.colorSlot != null && !taken) return snapshot;
    return snapshot.copyWith(colorSlot: () => _freeSlot(active));
  }

  /// Duplicates a prediction verbatim (same anchor date and projection) under
  /// a new id. It joins the Arena unless [archived]; throws [StateError] if
  /// the Arena is full.
  Future<PredictionSnapshot> clonePrediction(
    String id, {
    String? name,
    bool archived = false,
  }) async {
    final source = _requirePrediction(id);
    final copy = _placed(
      source.copyWith(
        id: _uuid.v4(),
        name: name ?? '${source.name} (copy)',
        archivedAt: () => null,
      ),
      active: !archived,
    );
    _predictions = [..._predictions, copy];
    notifyListeners();
    await _savePredictions();
    return copy;
  }

  /// Regenerates a prediction from today, starting at the current smoothed
  /// weight (or [weightKg]), keeping its id, name, calories, activity level,
  /// target, and horizon.
  Future<PredictionSnapshot> reanchorPrediction(
    String id, {
    double? weightKg,
  }) async {
    final source = _requirePrediction(id);
    final reanchored =
        _buildSnapshot(
          id: source.id,
          name: source.name,
          startWeightKg: weightKg ?? _requireCurrentWeight(),
          dailyCalories: source.dailyCalories,
          activityLevel: source.activityLevel,
          targetWeightKg: source.targetWeightKg,
          weeks: source.horizonWeeks,
        ).copyWith(
          colorSlot: () => source.colorSlot,
          archivedAt: () => source.archivedAt,
        );
    await _replacePrediction(reanchored);
    return reanchored;
  }

  PredictionSnapshot _buildSnapshot({
    required String id,
    required String name,
    required double startWeightKg,
    required double dailyCalories,
    required ActivityLevel activityLevel,
    required double? targetWeightKg,
    required int weeks,
  }) {
    final now = _clock();
    final points = LosertownMath.generateProjection(
      profile: _requireProfile(),
      startWeightKg: startWeightKg,
      dailyCalories: dailyCalories,
      activityLevel: activityLevel,
      startDate: now,
      weeks: weeks,
      targetWeightKg: targetWeightKg,
    );
    return PredictionSnapshot(
      id: id,
      name: name,
      createdAt: now,
      startWeightKg: startWeightKg,
      dailyCalories: dailyCalories,
      activityLevel: activityLevel,
      targetWeightKg: targetWeightKg,
      points: points,
    );
  }

  /// [p] as an active prediction holding a free color slot, or archived as
  /// of now.
  PredictionSnapshot _placed(PredictionSnapshot p, {required bool active}) {
    if (!active) {
      return p.copyWith(colorSlot: () => null, archivedAt: _clock);
    }
    final others = [
      for (final o in activePredictions)
        if (o.id != p.id) o,
    ];
    if (others.length >= maxActivePredictions) {
      throw StateError(
        'The Arena holds at most $maxActivePredictions predictions; '
        'archive one first',
      );
    }
    return p.copyWith(
      colorSlot: () => _freeSlot(others),
      archivedAt: () => null,
    );
  }

  /// The lowest color slot none of [active] holds.
  static int _freeSlot(Iterable<PredictionSnapshot> active) =>
      _freeSlotIn({for (final p in active) ?p.colorSlot});

  /// Keeps at most [maxActivePredictions] active, each in its own slot, by
  /// archiving the oldest extras and filling in missing slots. Repairs data
  /// saved before the archive existed, or brought in by [replaceAll].
  List<PredictionSnapshot> _normalized(List<PredictionSnapshot> predictions) {
    final newestActive = [
      for (final p in predictions)
        if (!p.isArchived) p,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final keep = {
      for (final p in newestActive.take(maxActivePredictions)) p.id,
    };
    final taken = <int>{};
    final result = [
      for (final p in predictions)
        if (p.isArchived || !keep.contains(p.id))
          p.copyWith(
            colorSlot: () => null,
            archivedAt: () => p.archivedAt ?? _clock(),
          )
        else if (p.colorSlot case final slot?
            when slot >= 0 && slot < maxActivePredictions && taken.add(slot))
          p
        else
          p.copyWith(colorSlot: () => null),
    ];
    return [
      for (final p in result)
        if (!p.isArchived && p.colorSlot == null)
          p.copyWith(colorSlot: () => _freeSlotIn(taken))
        else
          p,
    ];
  }

  /// Claims and returns the lowest slot not in [taken].
  static int _freeSlotIn(Set<int> taken) {
    var slot = 0;
    while (!taken.add(slot)) {
      slot++;
    }
    return slot;
  }

  Future<void> _replacePrediction(PredictionSnapshot updated) async {
    _predictions = [
      for (final p in _predictions) p.id == updated.id ? updated : p,
    ];
    notifyListeners();
    await _savePredictions();
  }

  // ---------------------------------------------------------------------------
  // Weight logs
  // ---------------------------------------------------------------------------

  Future<WeightLog> addWeightLog(double weightKg, {DateTime? date}) async {
    if (weightKg <= 0) {
      throw ArgumentError.value(weightKg, 'weightKg', 'must be > 0');
    }
    final log = WeightLog(
      id: _uuid.v4(),
      date: date ?? _clock(),
      weightKg: weightKg,
    );
    _weightLogs = [..._weightLogs, log]
      ..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    await _saveWeightLogs();
    return log;
  }

  /// Puts back a weigh-in removed earlier, e.g. for Undo.
  Future<void> restoreWeightLog(WeightLog log) async {
    if (_weightLogs.any((l) => l.id == log.id)) return;
    _weightLogs = [..._weightLogs, log]
      ..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    await _saveWeightLogs();
  }

  Future<void> deleteWeightLog(String id) async {
    _weightLogs = [
      for (final l in _weightLogs)
        if (l.id != id) l,
    ];
    notifyListeners();
    await _saveWeightLogs();
  }

  // ---------------------------------------------------------------------------
  // Checkpoints
  // ---------------------------------------------------------------------------

  Future<Checkpoint> addCheckpoint(String label, DateTime date) async {
    if (_checkpoints.length >= maxCheckpoints) {
      throw StateError('At most $maxCheckpoints checkpoints can be pinned');
    }
    final checkpoint = Checkpoint(
      id: _uuid.v4(),
      label: label.trim(),
      date: DateTime(date.year, date.month, date.day),
    );
    await _setCheckpoints([..._checkpoints, checkpoint]);
    return checkpoint;
  }

  Future<void> removeCheckpoint(String id) => _setCheckpoints([
    for (final c in _checkpoints)
      if (c.id != id) c,
  ]);

  /// Puts back a checkpoint removed earlier, e.g. for Undo.
  Future<void> restoreCheckpoint(Checkpoint checkpoint) async {
    if (_checkpoints.any((c) => c.id == checkpoint.id) ||
        _checkpoints.length >= maxCheckpoints) {
      return;
    }
    await _setCheckpoints([..._checkpoints, checkpoint]);
  }

  Future<void> _setCheckpoints(List<Checkpoint> checkpoints) async {
    _checkpoints = checkpoints..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    await _prefs.setString(
      _checkpointsKey,
      jsonEncode([for (final c in _checkpoints) c.toJson()]),
    );
  }

  // ---------------------------------------------------------------------------
  // Bulk data
  // ---------------------------------------------------------------------------

  /// Replaces everything at once (e.g. demo data), with one notification.
  Future<void> replaceAll({
    required UserProfile profile,
    required List<PredictionSnapshot> predictions,
    required List<WeightLog> weightLogs,
    List<Checkpoint> checkpoints = const [],
  }) async {
    _userProfile = profile;
    _predictions = _normalized(predictions);
    _weightLogs = [...weightLogs]..sort((a, b) => a.date.compareTo(b.date));
    _checkpoints = [...checkpoints]..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    await Future.wait([
      _prefs.setString(_profileKey, jsonEncode(profile.toJson())),
      _savePredictions(),
      _saveWeightLogs(),
      _prefs.setString(
        _checkpointsKey,
        jsonEncode([for (final c in _checkpoints) c.toJson()]),
      ),
    ]);
  }

  /// Deletes the profile, predictions, weigh-ins and checkpoints.
  Future<void> resetAll() async {
    _userProfile = null;
    _predictions = const [];
    _weightLogs = const [];
    _checkpoints = const [];
    notifyListeners();
    await Future.wait([
      for (final key in [
        _profileKey,
        _predictionsKey,
        _weightLogsKey,
        _checkpointsKey,
      ])
        _prefs.remove(key),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Display helpers
  // ---------------------------------------------------------------------------

  /// Stored kg value in the user's preferred unit.
  double displayWeight(double kg) => Units.fromKg(kg, unit);

  /// User-entered value in their preferred unit, converted to kg.
  double inputToKg(double value) => Units.toKg(value, unit);

  String formatWeight(double kg, {int decimals = 1, bool signed = false}) =>
      Units.format(kg, unit, decimals: decimals, signed: signed);

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  void _restore() {
    final profileJson = _prefs.getString(_profileKey);
    if (profileJson != null) {
      _userProfile = UserProfile.fromJson(
        jsonDecode(profileJson) as Map<String, dynamic>,
      );
    }
    final saved = _decodeList(
      _prefs.getString(_predictionsKey),
      PredictionSnapshot.fromJson,
    );
    _predictions = _normalized(saved);
    if (!listEquals(saved, _predictions)) unawaited(_savePredictions());
    _weightLogs = _decodeList(
      _prefs.getString(_weightLogsKey),
      WeightLog.fromJson,
    )..sort((a, b) => a.date.compareTo(b.date));
    _checkpoints = _decodeList(
      _prefs.getString(_checkpointsKey),
      Checkpoint.fromJson,
    )..sort((a, b) => a.date.compareTo(b.date));
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return [];
    return [
      for (final item in jsonDecode(raw) as List)
        fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> _savePredictions() => _prefs.setString(
    _predictionsKey,
    jsonEncode([for (final p in _predictions) p.toJson()]),
  );

  Future<void> _saveWeightLogs() => _prefs.setString(
    _weightLogsKey,
    jsonEncode([for (final l in _weightLogs) l.toJson()]),
  );

  // ---------------------------------------------------------------------------
  // Guards
  // ---------------------------------------------------------------------------

  UserProfile _requireProfile() =>
      _userProfile ?? (throw StateError('User profile has not been set'));

  double _requireCurrentWeight() =>
      currentWeightKg ??
      (throw StateError('No weight logs; pass a starting weight explicitly'));

  PredictionSnapshot _requirePrediction(String id) =>
      predictionById(id) ?? (throw StateError('No prediction with id $id'));
}
