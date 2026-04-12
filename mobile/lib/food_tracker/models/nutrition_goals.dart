import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// User-defined daily nutrition targets.
class NutritionGoals {
  final double calories;
  final double protein; // g
  final double carbs; // g
  final double fat; // g
  final double iron; // mg

  const NutritionGoals({
    this.calories = 2000,
    this.protein = 50,
    this.carbs = 275,
    this.fat = 78,
    this.iron = 18,
  });

  Map<String, dynamic> toMap() => {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'iron': iron,
      };

  factory NutritionGoals.fromMap(Map<String, dynamic> m) => NutritionGoals(
        calories: (m['calories'] as num).toDouble(),
        protein: (m['protein'] as num).toDouble(),
        carbs: (m['carbs'] as num).toDouble(),
        fat: (m['fat'] as num).toDouble(),
        iron: (m['iron'] as num).toDouble(),
      );

  NutritionGoals copyWith({
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? iron,
  }) =>
      NutritionGoals(
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        iron: iron ?? this.iron,
      );

  // ── SharedPreferences persistence ─────────────────────────────────────────

  static const _key = 'nutrition_goals';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toMap()));
  }

  static Future<NutritionGoals> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const NutritionGoals();
    try {
      return NutritionGoals.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const NutritionGoals();
    }
  }
}
