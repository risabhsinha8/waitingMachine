import 'package:flutter_test/flutter_test.dart';
import 'package:losertown/services/bmi_rank.dart';

void main() {
  group('ladder', () {
    test('maps BMI bands to ranks, healthy at the top', () {
      expect(BmiRank.forBmi(17), BmiRank.featherweight);
      expect(BmiRank.forBmi(18.5), BmiRank.legend);
      expect(BmiRank.forBmi(24.9), BmiRank.legend);
      expect(BmiRank.forBmi(25), BmiRank.eliteRanger);
      expect(BmiRank.forBmi(27.5), BmiRank.journeymanBurner);
      expect(BmiRank.forBmi(30), BmiRank.apprenticeShredder);
      expect(BmiRank.forBmi(35), BmiRank.trailScout);
      expect(BmiRank.forBmi(40), BmiRank.freshRecruit);
      expect(BmiRank.forBmi(60), BmiRank.freshRecruit);
    });

    test('levels climb one at a time to Legend', () {
      expect(BmiRank.ladder.map((r) => r.level), [1, 2, 3, 4, 5, 6]);
      expect(BmiRank.freshRecruit.next, BmiRank.trailScout);
      expect(BmiRank.eliteRanger.next, BmiRank.legend);
      expect(BmiRank.legend.next, isNull);
      // Underweight isn't a higher level; it leads back to Legend.
      expect(BmiRank.featherweight.level, 0);
      expect(BmiRank.featherweight.next, BmiRank.legend);
    });

    test('bands cover every BMI without gaps', () {
      for (var bmi = 10.0; bmi < 70; bmi += 0.05) {
        final rank = BmiRank.forBmi(bmi);
        expect(bmi >= rank.minBmi && bmi < rank.maxBmi, isTrue, reason: '$bmi');
      }
    });
  });

  group('status', () {
    test('BMI and weight convert both ways', () {
      expect(bmiOf(81, 180), closeTo(25, 1e-9));
      expect(weightForBmi(25, 180), closeTo(81, 1e-9));
    });

    test('weight to lose for the next rank', () {
      // BMI 27.0 at 180 cm: Elite Ranger, Legend below 81 kg.
      final s = RankStatus(weightKg: 87.48, heightCm: 180);
      expect(s.rank, BmiRank.eliteRanger);
      expect(s.kgToNext, closeTo(6.48, 1e-6));
      expect(s.progress, inInclusiveRange(0, 1));
    });

    test('Featherweights gain back to Legend; Legends are done', () {
      final light = RankStatus(weightKg: 56.7, heightCm: 180); // BMI 17.5
      expect(light.rank, BmiRank.featherweight);
      expect(light.kgToNext, closeTo(56.7 - weightForBmi(18.5, 180), 1e-9));
      expect(light.kgToNext! < 0, isTrue);

      final legend = RankStatus(weightKg: 70, heightCm: 180);
      expect(legend.rank, BmiRank.legend);
      expect(legend.kgToNext, isNull);
      expect(legend.progress, 1);
    });

    test('progress grows as BMI falls through a band', () {
      double at(double bmi) =>
          RankStatus(weightKg: weightForBmi(bmi, 180), heightCm: 180).progress;
      expect(at(31), greaterThan(at(34.9)));
      expect(at(50), 0); // open-ended first band, measured from BMI 45
    });
  });
}
