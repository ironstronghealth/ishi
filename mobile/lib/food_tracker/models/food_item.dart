/// Normalized food model used throughout the tracker.
/// Built from USDA FoodData Central API responses or manual entry.
class FoodItem {
  final String id; // USDA fdcId or generated UUID
  final String name;
  final double calories; // kcal per 100 g (or per serving if servingSize != 100)
  final double protein; // grams
  final double carbs; // grams
  final double fat; // grams
  final double iron; // milligrams
  final double servingSize; // grams — default serving used for multiplier math
  final String? brand; // optional brand label from USDA

  const FoodItem({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.iron,
    this.servingSize = 100.0,
    this.brand,
  });

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'iron': iron,
        'servingSize': servingSize,
        'brand': brand,
      };

  factory FoodItem.fromMap(Map<String, dynamic> m) => FoodItem(
        id: m['id'] as String,
        name: m['name'] as String,
        calories: (m['calories'] as num).toDouble(),
        protein: (m['protein'] as num).toDouble(),
        carbs: (m['carbs'] as num).toDouble(),
        fat: (m['fat'] as num).toDouble(),
        iron: (m['iron'] as num).toDouble(),
        servingSize: (m['servingSize'] as num).toDouble(),
        brand: m['brand'] as String?,
      );

  // ── Factory: parse a single USDA FoodData Central search-result item ───────
  /// [raw] is one element from `data['foods']` in the search endpoint.
  factory FoodItem.fromUsda(Map<String, dynamic> raw) {
    double _n(String name) {
      final nutrients = raw['foodNutrients'];
      if (nutrients is! List) return 0.0;
      for (final n in nutrients) {
        final nName = n['nutrientName'] as String? ?? '';
        if (nName == name) return (n['value'] as num? ?? 0).toDouble();
      }
      return 0.0;
    }

    // USDA uses several calorie nutrient names depending on data type
    double calories = _n('Energy');
    if (calories == 0) calories = _n('Energy (Atwater General Factors)');
    if (calories == 0) calories = _n('Energy (Atwater Specific Factors)');

    return FoodItem(
      id: (raw['fdcId'] ?? 0).toString(),
      name: (raw['description'] ?? 'Unknown food').toString(),
      calories: calories,
      protein: _n('Protein'),
      carbs: _n('Carbohydrate, by difference'),
      fat: _n('Total lipid (fat)'),
      iron: _n('Iron, Fe'),
      servingSize: 100.0, // USDA values are per 100 g by default
      brand: raw['brandOwner'] as String?,
    );
  }

  @override
  String toString() => 'FoodItem($name, ${calories.toStringAsFixed(0)} kcal)';
}
