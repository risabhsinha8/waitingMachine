import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/models/app_models.dart';
import 'package:losertown/screens/arena/timeline_chart_data.dart';
import 'package:losertown/services/losertown_math.dart';
import 'package:losertown/utils/units.dart';

final now = DateTime(2026, 10, 26, 9);

PredictionSnapshot linear(String id, DateTime start, double rateKg) =>
    PredictionSnapshot(
      id: id,
      name: id,
      createdAt: start,
      startWeightKg: 100,
      dailyCalories: 2000,
      activityLevel: ActivityLevel.sedentary,
      points: [
        for (var w = 0; w <= 52; w++)
          WeeklyProjectionPoint(
            weekNumber: w,
            date: DateTime(start.year, start.month, start.day + 7 * w),
            projectedWeightKg: 100 + rateKg * w,
            weeklyChangeKg: w == 0 ? 0 : rateKg,
            dynamicTdee: 2500,
          ),
      ],
    );

List<SmoothedWeight> smooth(Map<int, double> byDayOffset) =>
    LosertownMath.smoothWeights([
      for (final e in byDayOffset.entries)
        WeightLog(
          id: '${e.key}',
          date: DateTime(2026, 10, 26 + e.key, 7),
          weightKg: e.value,
        ),
    ]);

TimelineChartData build({
  ChartWindow window = ChartWindow.days30,
  List<PredictionSnapshot> predictions = const [],
  Set<String> hidden = const {},
  List<SmoothedWeight> smoothed = const [],
  WeightUnit unit = WeightUnit.kg,
}) => TimelineChartData.build(
  window: window,
  now: now,
  predictions: predictions,
  hiddenIds: hidden,
  smoothed: smoothed,
  unit: unit,
);

void main() {
  test('trailing windows end with a quarter-span look-ahead', () {
    final d30 = build();
    expect(d30.start, DateTime(2026, 9, 26));
    expect(d30.end, DateTime(2026, 11, 2)); // min 7 days ahead
    expect(d30.xOf(d30.today), 30);

    final d90 = build(window: ChartWindow.days90);
    expect(d90.end, DateTime(2026, 11, 17)); // 90 ~/ 4 = 22 days ahead
  });

  test('"All" starts at the earliest prediction or weigh-in', () {
    final data = build(
      window: ChartWindow.all,
      predictions: [linear('p', DateTime(2026, 6, 1), -0.5)],
      smoothed: smooth({-30: 90}),
    );
    expect(data.start, DateTime(2026, 6, 1));
  });

  test('predictions are clipped to the window and keep their slots', () {
    final older = linear('older', DateTime(2026, 8, 3), -1);
    final hidden = linear('hidden', DateTime(2026, 10, 1), -0.5);
    final newer = linear('newer', DateTime(2026, 10, 19), -0.5);
    final data = build(predictions: [older, hidden, newer], hidden: {'hidden'});

    expect(data.predictionSeries.map((s) => s.prediction.id), [
      'older',
      'newer',
    ]);
    // Hiding the middle one must not shift the last one's color slot.
    expect(data.predictionSeries.last.slot, 2);

    // 'older' started before the window: its curve begins at the left edge,
    // at the interpolated projection for that day.
    final first = data.predictionSeries.first.spots.first;
    expect(first.x, 0);
    expect(first.y, LosertownMath.expectedWeightOn(older, data.start));

    // 'newer' starts mid-window, at its anchor.
    expect(data.predictionSeries.last.spots.first.x, 23);
    expect(data.predictionSeries.last.spots.last.x, data.maxX);
  });

  test('plots in the display unit', () {
    final data = build(smoothed: smooth({0: 80}), unit: WeightUnit.lbs);
    expect(data.trendSpots.single.y, closeTo(Units.kgToLbs(80), 1e-9));
    expect(data.minY, lessThan(data.trendSpots.single.y));
    expect(data.maxY, greaterThan(data.trendSpots.single.y));
  });

  test('trend is interpolated between weigh-ins, raw only on logged days', () {
    final smoothed = smooth({-4: 90, 0: 88});
    final data = build(smoothed: smoothed);
    final a = smoothed.first.smoothedWeightKg;
    final b = smoothed.last.smoothedWeightKg;

    expect(data.trendOn(DateTime(2026, 10, 22)), a);
    expect(data.trendOn(DateTime(2026, 10, 24)), closeTo((a + b) / 2, 1e-9));
    expect(data.trendOn(DateTime(2026, 10, 20)), isNull);
    expect(data.trendOn(DateTime(2026, 10, 27)), isNull);

    expect(data.rawOn(DateTime(2026, 10, 22)), 90);
    expect(data.rawOn(DateTime(2026, 10, 24)), isNull);
  });

  test('tooltip readings list active predictions, heaviest first', () {
    final slow = linear('slow', DateTime(2026, 10, 5), -0.25);
    final fast = linear('fast', DateTime(2026, 10, 5), -1);
    final future = linear('future', DateTime(2026, 10, 30), -0.5);
    final data = build(predictions: [fast, slow, future]);

    final readings = data.projectionsOn(DateTime(2026, 10, 26));
    expect(readings.map((r) => r.prediction.id), ['slow', 'fast']);
    expect(readings.first.weightKg, closeTo(100 - 0.75, 1e-9));
    expect(readings.last.slot, 0);
  });

  test('defaults to the smallest window that fits the history', () {
    expect(ChartWindow.fitting(null, now), ChartWindow.days30);
    expect(ChartWindow.fitting(DateTime(2026, 10, 5), now), ChartWindow.days30);
    expect(ChartWindow.fitting(DateTime(2026, 8, 1), now), ChartWindow.days90);
    expect(ChartWindow.fitting(DateTime(2026, 6, 1), now), ChartWindow.months6);
    expect(ChartWindow.fitting(DateTime(2025, 1, 1), now), ChartWindow.all);
  });

  test('y steps never need rounding to label', () {
    // A 10 kg spread would have picked 2.5 kg steps (97.5 shown as "98").
    final data = build(smoothed: smooth({-20: 100, 0: 90}));
    expect([0.5, 1.0, 2.0, 5.0, 10.0], contains(data.yInterval));
    expect(data.minY % data.yInterval, 0);
  });

  test('empty when there is nothing to plot', () {
    expect(build().isEmpty, isTrue);
  });
}
