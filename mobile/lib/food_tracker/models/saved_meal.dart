import 'dart:convert';
import 'food_item.dart';

/// One food + portion within a saved meal template.
class SavedMealItem {
  final FoodItem foodItem;
  final double quantityMultiplier;

  const SavedMealItem({
    required this.foodItem,
    required this.quantityMultiplier,
  });

  double get calories => foodItem.calories * quantityMultiplier;
  double get protein => foodItem.protein * quantityMultiplier;
  double get carbs => foodItem.carbs * quantityMultiplier;
  double get fat => foodItem.fat * quantityMultiplier;
  double get iron => foodItem.iron * quantityMultiplier;
  double get grams => foodItem.servingSize * quantityMultiplier;

  Map<String, dynamic> toMap() => {
        'foodItem': foodItem.toMap(),
        'quantityMultiplier': quantityMultiplier,
      };

  factory SavedMealItem.fromMap(Map<String, dynamic> m) => SavedMealItem(
        foodItem: FoodItem.fromMap(m['foodItem'] as Map<String, dynamic>),
        quantityMultiplier: (m['quantityMultiplier'] as num).toDouble(),
      );

  SavedMealItem copyWith({double? quantityMultiplier}) => SavedMealItem(
        foodItem: foodItem,
        quantityMultiplier: quantityMultiplier ?? this.quantityMultiplier,
      );
}

/// A named meal template made up of multiple food items.
/// Saved by the user for quick re-logging.
class SavedMeal {
  final String id;
  final String name;
  final List<SavedMealItem> items;

  const SavedMeal({
    required this.id,
    required this.name,
    required this.items,
  });

  double get totalCalories => items.fold(0.0, (s, i) => s + i.calories);
  double get totalProtein => items.fold(0.0, (s, i) => s + i.protein);
  double get totalCarbs => items.fold(0.0, (s, i) => s + i.carbs);
  double get totalFat => items.fold(0.0, (s, i) => s + i.fat);
  double get totalIron => items.fold(0.0, (s, i) => s + i.iron);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'items': jsonEncode(items.map((i) => i.toMap()).toList()),
      };

  factory SavedMeal.fromMap(Map<String, dynamic> m) {
    final raw = jsonDecode(m['items'] as String) as List;
    return SavedMeal(
      id: m['id'] as String,
      name: m['name'] as String,
      items: raw.map((i) => SavedMealItem.fromMap(i as Map<String, dynamic>)).toList(),
    );
  }

  SavedMeal copyWith({String? name, List<SavedMealItem>? items}) => SavedMeal(
        id: id,
        name: name ?? this.name,
        items: items ?? this.items,
      );
}
