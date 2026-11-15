import 'package:flutter_test/flutter_test.dart';
import 'package:ishi_mobile/food_tracker/models/food_item.dart';
import 'package:ishi_mobile/food_tracker/models/library_food.dart';
import 'package:ishi_mobile/food_tracker/screens/serving_size_screen.dart';

FoodItem _food({
  double servingSize = 100,
  List<FoodPortion> portions = const [],
}) =>
    FoodItem(
      id: '1',
      name: 'Test',
      calories: 100,
      protein: 1,
      carbs: 1,
      fat: 1,
      iron: 1,
      servingSize: servingSize,
      portions: portions,
    );

void main() {
  group('FoodPortion.listFromUsdaDetail', () {
    test('builds labels from amount, unit and modifier', () {
      final portions = FoodPortion.listFromUsdaDetail({
        'foodPortions': [
          {
            'gramWeight': 21.0,
            'amount': 1.0,
            'modifier': 'slice',
            'measureUnit': {'name': 'undetermined'},
          },
          {
            'gramWeight': 249.0,
            'amount': 1.0,
            'modifier': '',
            'measureUnit': {'name': 'cup'},
          },
          {'gramWeight': 0, 'amount': 1.0, 'modifier': 'ignored'},
          {
            'gramWeight': 21.0,
            'amount': 1.0,
            'modifier': 'slice', // duplicate label
            'measureUnit': {'name': 'undetermined'},
          },
        ],
      });

      expect(portions.map((p) => p.label), ['1 slice', '1 cup']);
      expect(portions.map((p) => p.grams), [21.0, 249.0]);
    });

    test('tolerates missing data', () {
      expect(FoodPortion.listFromUsdaDetail({}), isEmpty);
      expect(FoodPortion.listFromUsdaDetail({'foodPortions': 'x'}), isEmpty);
    });
  });

  group('FoodItem', () {
    test('portions survive a serialization round trip', () {
      final food = _food(
        portions: const [FoodPortion(label: '1 cup', grams: 240)],
      );
      final copy = FoodItem.fromMap(food.toMap());
      expect(copy.portions.single.label, '1 cup');
      expect(copy.portions.single.grams, 240);
    });

    test('reads entries saved before portions existed', () {
      final map = _food().toMap()..remove('portions');
      expect(FoodItem.fromMap(map).portions, isEmpty);
    });

    test('fromUsda takes the label serving of branded foods', () {
      final food = FoodItem.fromUsda({
        'fdcId': 2517161,
        'description': 'Cereal',
        'servingSize': 20.0,
        'servingSizeUnit': 'GRM',
        'householdServingFullText': '3/4 cup',
        'foodNutrients': [],
      });
      expect(food.portions.single.label, '3/4 cup');
      expect(food.portions.single.grams, 20);
    });
  });

  group('serving units', () {
    test('lists default serving, portions, then grams', () {
      final units = servingUnitsFor(_food(
        portions: const [FoodPortion(label: '1 cup', grams: 240)],
      ));
      expect(units.map((u) => u.label), ['100 g', 'cup (240 g)', 'g']);
      expect(units.map((u) => u.grams), [100, 240, 1]);
    });

    test('labels a non-100 g serving as a serving', () {
      final units = servingUnitsFor(_food(servingSize: 15));
      expect(units.first.label, 'serving (15 g)');
    });

    test('bestUnitFor recovers the unit an entry was logged in', () {
      final units = servingUnitsFor(_food(
        portions: const [FoodPortion(label: '1 cup', grams: 240)],
      ));
      expect(bestUnitFor(units, 480), (1, 2.0)); // 2 cups
      expect(bestUnitFor(units, 150), (0, 1.5)); // 1.5 × 100 g
      final (index, qty) = bestUnitFor(units, 137); // awkward amount
      expect(index, 0);
      expect(qty, closeTo(1.37, 0.0001));
    });
  });

  group('LibraryFood', () {
    test('is only kept while something references it', () {
      final f = LibraryFood(food: _food());
      expect(f.isWorthKeeping, isFalse);
      expect(f.copyWith(isFavorite: true).isWorthKeeping, isTrue);
      expect(f.copyWith(useCount: 1).isWorthKeeping, isTrue);
      expect(f.copyWith(barcode: '12345678').isWorthKeeping, isTrue);
    });
  });
}
