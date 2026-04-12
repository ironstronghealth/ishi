import 'dart:convert';
import 'food_item.dart';

/// Represents one logged meal event.
/// Nutrients are scaled by [quantityMultiplier] relative to [foodItem.servingSize].
class MealEntry {
  final String id; // UUID
  final FoodItem foodItem;
  final double quantityMultiplier; // e.g. 1.5 = 1.5 × servingSize
  final DateTime timestamp;
  final MealType mealType;

  const MealEntry({
    required this.id,
    required this.foodItem,
    required this.quantityMultiplier,
    required this.timestamp,
    required this.mealType,
  });

  // ── Derived nutrient values (scaled) ──────────────────────────────────────

  double get calories => foodItem.calories * quantityMultiplier;
  double get protein => foodItem.protein * quantityMultiplier;
  double get carbs => foodItem.carbs * quantityMultiplier;
  double get fat => foodItem.fat * quantityMultiplier;
  double get iron => foodItem.iron * quantityMultiplier;
  double get servingGrams => foodItem.servingSize * quantityMultiplier;

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'foodItem': jsonEncode(foodItem.toMap()),
        'quantityMultiplier': quantityMultiplier,
        'timestamp': timestamp.toIso8601String(),
        'mealType': mealType.name,
      };

  factory MealEntry.fromMap(Map<String, dynamic> m) => MealEntry(
        id: m['id'] as String,
        foodItem: FoodItem.fromMap(
          jsonDecode(m['foodItem'] as String) as Map<String, dynamic>,
        ),
        quantityMultiplier: (m['quantityMultiplier'] as num).toDouble(),
        timestamp: DateTime.parse(m['timestamp'] as String),
        mealType: MealType.values.firstWhere(
          (e) => e.name == m['mealType'],
          orElse: () => MealType.snack,
        ),
      );

  /// Returns a copy with updated fields.
  MealEntry copyWith({
    double? quantityMultiplier,
    MealType? mealType,
  }) =>
      MealEntry(
        id: id,
        foodItem: foodItem,
        quantityMultiplier: quantityMultiplier ?? this.quantityMultiplier,
        timestamp: timestamp,
        mealType: mealType ?? this.mealType,
      );
}

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack;

  String get label {
    switch (this) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
      case MealType.snack:
        return 'Snack';
    }
  }
}
