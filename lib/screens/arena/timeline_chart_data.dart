import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

import '../../models/app_models.dart';
import '../../services/losertown_math.dart';
import '../../utils/units.dart';

enum ChartWindow {
  days30('30D', 30),
  days90('90D', 90),
  months6('6M', 182),
  all('All', null);

  const ChartWindow(this.label, this.days);
  final String label;

  /// Trailing days shown before today; null shows all history.
  final int? days;

  /// The smallest window that still shows everything since [earliest].
  static ChartWindow fitting(DateTime? earliest, DateTime now) {
    if (earliest == null) return ChartWindow.days30;
    final age = now.difference(earliest).inDays;
    for (final w in values) {
      if (w.days == null || age <= w.days!) return w;
    }
    return ChartWindow.all;
  }
}

/// A visible prediction's curve. [slot] is its fixed color/dash slot.
class PredictionSeries {
  const PredictionSeries({
    required this.prediction,
    required this.slot,
    required this.spots,
  });

  final PredictionSnapshot prediction;
  final int slot;
  final List<FlSpot> spots;
}

/// One prediction's value on a hovered day, for the tooltip.
class ProjectionReading {
  const ProjectionReading(this.prediction, this.slot, this.weightKg);

  final PredictionSnapshot prediction;
  final int slot;
  final double weightKg;
}

/// Everything the Arena chart plots, in chart coordinates: x is whole days
/// since [start], y is weight in the display unit.
class TimelineChartData {
  TimelineChartData._({
    required this.start,
    required this.end,
    required this.today,
    required this.unit,
    required this.predictionSeries,
    required this.trendSpots,
    required this.rawSpots,
    required this.minY,
    required this.maxY,
    required this.yInterval,
    required this.xInterval,
    required List<SmoothedWeight> smoothed,
  }) : _smoothed = smoothed;

  /// Builds the chart for [window]. Each series takes its prediction's
  /// persisted color slot (falling back to its position), so hiding or
  /// archiving one never repaints the others.
  factory TimelineChartData.build({
    required ChartWindow window,
    required DateTime now,
    required List<PredictionSnapshot> predictions,
    required Set<String> hiddenIds,
    required List<SmoothedWeight> smoothed,
    required WeightUnit unit,
  }) {
    final today = _day(now);
    final DateTime start;
    final int span;
    if (window.days case final days?) {
      start = today.subtract(Duration(days: days));
      span = days;
    } else {
      final earliest = [
        if (smoothed.isNotEmpty) smoothed.first.date,
        for (final p in predictions) _day(p.createdAt),
      ].fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
      start = earliest == null || !earliest.isBefore(today)
          ? today.subtract(const Duration(days: 30))
          : earliest;
      span = _daysBetween(start, today);
    }
    // A short look-ahead shows where each timeline is heading.
    final end = today.add(Duration(days: math.max(7, span ~/ 4)));

    double x(DateTime d) => _daysBetween(start, d).toDouble();
    double y(double kg) => Units.fromKg(kg, unit);
    bool inRange(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

    final series = <PredictionSeries>[];
    for (final (i, p) in predictions.indexed) {
      if (hiddenIds.contains(p.id) || p.points.isEmpty) continue;
      final slot = p.colorSlot ?? i;
      final from = _later(start, _day(p.createdAt));
      final to = _earlier(end, _day(p.points.last.date));
      if (from.isAfter(to)) continue;
      final spots = [
        FlSpot(x(from), y(LosertownMath.expectedWeightOn(p, from))),
        for (final point in p.points)
          if (point.date.isAfter(from) && point.date.isBefore(to))
            FlSpot(x(point.date), y(point.projectedWeightKg)),
        if (to.isAfter(from))
          FlSpot(x(to), y(LosertownMath.expectedWeightOn(p, to))),
      ];
      series.add(PredictionSeries(prediction: p, slot: slot, spots: spots));
    }

    final visible = [
      for (final s in smoothed)
        if (inRange(s.date)) s,
    ];
    final trendSpots = [
      for (final s in visible) FlSpot(x(s.date), y(s.smoothedWeightKg)),
    ];
    final rawSpots = [
      for (final s in visible) FlSpot(x(s.date), y(s.rawWeightKg)),
    ];

    final ys = [
      for (final s in series) ...s.spots.map((p) => p.y),
      ...trendSpots.map((p) => p.y),
      ...rawSpots.map((p) => p.y),
    ];
    final lo = ys.isEmpty ? 0.0 : ys.reduce(math.min);
    final hi = ys.isEmpty ? 1.0 : ys.reduce(math.max);
    final pad = math.max((hi - lo) * 0.08, 0.3);
    final yInterval = _niceStep((hi - lo + 2 * pad) / 4);

    return TimelineChartData._(
      start: start,
      end: end,
      today: today,
      unit: unit,
      predictionSeries: series,
      trendSpots: trendSpots,
      rawSpots: rawSpots,
      minY: ((lo - pad) / yInterval).floorToDouble() * yInterval,
      maxY: ((hi + pad) / yInterval).ceilToDouble() * yInterval,
      yInterval: yInterval,
      xInterval: _niceDays(_daysBetween(start, end)),
      smoothed: smoothed,
    );
  }

  final DateTime start;
  final DateTime end;
  final DateTime today;
  final WeightUnit unit;
  final List<PredictionSeries> predictionSeries;
  final List<FlSpot> trendSpots;
  final List<FlSpot> rawSpots;
  final double minY;
  final double maxY;
  final double yInterval;
  final double xInterval;
  final List<SmoothedWeight> _smoothed;

  bool get isEmpty => predictionSeries.isEmpty && trendSpots.isEmpty;

  double get maxX => xOf(end);
  double xOf(DateTime date) => _daysBetween(start, date).toDouble();
  DateTime dateOf(double x) =>
      DateTime(start.year, start.month, start.day + x.round());

  /// The 7-day trend on [day], interpolated between weigh-in days; null
  /// outside the logged range.
  double? trendOn(DateTime day) {
    final d = _day(day);
    for (var i = 0; i < _smoothed.length; i++) {
      final s = _smoothed[i];
      if (s.date == d) return s.smoothedWeightKg;
      if (s.date.isAfter(d)) {
        if (i == 0) return null;
        final prev = _smoothed[i - 1];
        final t = _daysBetween(prev.date, d) / _daysBetween(prev.date, s.date);
        return prev.smoothedWeightKg +
            (s.smoothedWeightKg - prev.smoothedWeightKg) * t;
      }
    }
    return null;
  }

  /// The raw scale weight if one was logged on [day].
  double? rawOn(DateTime day) {
    final d = _day(day);
    for (final s in _smoothed) {
      if (s.date == d) return s.rawWeightKg;
    }
    return null;
  }

  /// Each visible prediction's projection on [day], heaviest first so the
  /// tooltip reads in the same order as the lines.
  List<ProjectionReading> projectionsOn(DateTime day) {
    final d = _day(day);
    return [
      for (final s in predictionSeries)
        if (!d.isBefore(_day(s.prediction.createdAt)) &&
            !d.isAfter(_day(s.prediction.points.last.date)))
          ProjectionReading(
            s.prediction,
            s.slot,
            LosertownMath.expectedWeightOn(s.prediction, d),
          ),
    ]..sort((a, b) => b.weightKg.compareTo(a.weightKg));
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  static double _niceStep(double raw) {
    // Halves only below 1, so whole-number labels never need rounding.
    for (final step in const [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]) {
      if (step >= raw) return step;
    }
    return 100;
  }

  /// Label spacing in days, aiming for about four date labels.
  static double _niceDays(int span) {
    for (final days in const [7, 14, 30, 61, 91, 182, 365]) {
      if (span / days <= 4.5) return days.toDouble();
    }
    return 730;
  }
}
