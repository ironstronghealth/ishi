import 'package:flutter_test/flutter_test.dart';
import 'package:ishi_mobile/food_tracker/services/barcode_service.dart';

void main() {
  group('BarcodeService.isValidBarcode', () {
    test('accepts retail barcode lengths', () {
      expect(BarcodeService.isValidBarcode('12345678'), isTrue);
      expect(BarcodeService.isValidBarcode('012345678905'), isTrue);
      expect(BarcodeService.isValidBarcode('3017620422003'), isTrue);
    });

    test('rejects other input', () {
      expect(BarcodeService.isValidBarcode(''), isFalse);
      expect(BarcodeService.isValidBarcode('1234567890'), isFalse);
      expect(BarcodeService.isValidBarcode('30176204220o3'), isFalse);
      expect(BarcodeService.isValidBarcode('https://example.com'), isFalse);
    });
  });

  group('BarcodeService.parseOpenFoodFacts', () {
    test('scales per-100g values to the label serving and converts iron', () {
      final food = BarcodeService.parseOpenFoodFacts('3017620422003', {
        'product_name': 'Hazelnut Spread',
        'brands': 'Acme, Other',
        'serving_quantity': '15',
        'nutriments': {
          'energy-kcal_100g': 540,
          'proteins_100g': 6,
          'carbohydrates_100g': 58,
          'fat_100g': 30,
          'iron_100g': 0.004, // grams
        },
      })!;

      expect(food.id, 'off_3017620422003');
      expect(food.brand, 'Acme');
      expect(food.servingSize, 15);
      expect(food.calories, closeTo(81, 0.001));
      expect(food.protein, closeTo(0.9, 0.001));
      expect(food.iron, closeTo(0.6, 0.001)); // 4 mg/100 g × 0.15
    });

    test('falls back to 100 g basis and kJ energy', () {
      final food = BarcodeService.parseOpenFoodFacts('12345678', {
        'product_name': 'Oats',
        'nutriments': {'energy_100g': 1569, 'proteins_100g': 13},
      })!;

      expect(food.servingSize, 100);
      expect(food.calories, closeTo(375, 0.5));
      expect(food.brand, isNull);
    });

    test('returns null without a name or nutrition facts', () {
      expect(
        BarcodeService.parseOpenFoodFacts('12345678', {
          'nutriments': {'energy-kcal_100g': 100},
        }),
        isNull,
      );
      expect(
        BarcodeService.parseOpenFoodFacts('12345678', {
          'product_name': 'Mystery',
          'nutriments': <String, dynamic>{},
        }),
        isNull,
      );
    });
  });
}
