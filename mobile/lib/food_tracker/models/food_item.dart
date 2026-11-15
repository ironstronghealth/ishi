/// A named household measure for a food, e.g. "1 cup" = 240 g.
class FoodPortion {
  final String label;
  final double grams;

  const FoodPortion({required this.label, required this.grams});

  Map<String, dynamic> toMap() => {'label': label, 'grams': grams};

  static FoodPortion? tryFromMap(dynamic m) {
    if (m is! Map) return null;
    final label = m['label'];
    final grams = m['grams'];
    if (label is! String || label.isEmpty || grams is! num || grams <= 0) {
      return null;
    }
    return FoodPortion(label: label, grams: grams.toDouble());
  }

  /// Parses `foodPortions` from the USDA food-detail endpoint.
  static List<FoodPortion> listFromUsdaDetail(Map<String, dynamic> data) {
    final raw = data['foodPortions'];
    if (raw is! List) return const [];

    final seen = <String>{};
    final out = <FoodPortion>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final grams = (p['gramWeight'] as num?)?.toDouble() ?? 0;
      if (grams <= 0) continue;

      final amount = (p['amount'] as num?)?.toDouble() ?? 1;
      final measureUnit = p['measureUnit'];
      final unit =
          measureUnit is Map ? (measureUnit['name'] ?? '').toString() : '';
      final parts = [
        _fmtAmount(amount),
        if (unit.isNotEmpty && unit != 'undetermined') unit,
        (p['modifier'] ?? p['portionDescription'] ?? '').toString().trim(),
      ].where((s) => s.isNotEmpty);
      final label = parts.join(' ');
      if (seen.add(label.toLowerCase())) {
        out.add(FoodPortion(label: label, grams: grams));
      }
    }
    return out;
  }

  static String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

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

  /// Household measures ("1 cup", "1 slice") the user can log in. May be
  /// empty; the serving screen always offers grams as well.
  final List<FoodPortion> portions;

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
    this.portions = const [],
  });

  FoodItem copyWith({List<FoodPortion>? portions}) => FoodItem(
        id: id,
        name: name,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        iron: iron,
        servingSize: servingSize,
        brand: brand,
        portions: portions ?? this.portions,
      );

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
        if (portions.isNotEmpty)
          'portions': portions.map((p) => p.toMap()).toList(),
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
        portions: (m['portions'] as List? ?? const [])
            .map(FoodPortion.tryFromMap)
            .whereType<FoodPortion>()
            .toList(),
      );

  // ── Factory: parse a single USDA FoodData Central search-result item ───────
  /// [raw] is one element from `data['foods']` in the search endpoint.
  factory FoodItem.fromUsda(Map<String, dynamic> raw) {
    double nutrient(String name) {
      final nutrients = raw['foodNutrients'];
      if (nutrients is! List) return 0.0;
      for (final n in nutrients) {
        final nName = n['nutrientName'] as String? ?? '';
        if (nName == name) return (n['value'] as num? ?? 0).toDouble();
      }
      return 0.0;
    }

    // USDA uses several calorie nutrient names depending on data type
    double calories = nutrient('Energy');
    if (calories == 0) calories = nutrient('Energy (Atwater General Factors)');
    if (calories == 0) calories = nutrient('Energy (Atwater Specific Factors)');

    return FoodItem(
      id: (raw['fdcId'] ?? 0).toString(),
      name: (raw['description'] ?? 'Unknown food').toString(),
      calories: calories,
      protein: nutrient('Protein'),
      carbs: nutrient('Carbohydrate, by difference'),
      fat: nutrient('Total lipid (fat)'),
      iron: nutrient('Iron, Fe'),
      servingSize: 100.0, // USDA values are per 100 g by default
      brand: raw['brandOwner'] as String?,
      portions: _usdaSearchPortions(raw),
    );
  }

  /// Portions available directly on a USDA search result. Branded foods
  /// carry their label serving; other data types need the detail endpoint
  /// (see UsdaService.fetchPortions).
  static List<FoodPortion> _usdaSearchPortions(Map<String, dynamic> raw) {
    final out = <FoodPortion>[];

    final size = (raw['servingSize'] as num?)?.toDouble() ?? 0;
    final unit = (raw['servingSizeUnit'] ?? '').toString().toLowerCase();
    // Millilitres are treated as grams — close enough for drinks, and USDA
    // gives no density for branded products.
    if (size > 0 && const {'g', 'grm', 'ml', 'mlt'}.contains(unit)) {
      final household =
          (raw['householdServingFullText'] ?? '').toString().trim();
      out.add(FoodPortion(
        label: household.isEmpty ? '1 serving' : household,
        grams: size,
      ));
    }

    final measures = raw['foodMeasures'];
    if (measures is List) {
      for (final m in measures) {
        if (m is! Map) continue;
        final label = (m['disseminationText'] ?? '').toString().trim();
        final grams = (m['gramWeight'] as num?)?.toDouble() ?? 0;
        if (label.isNotEmpty && grams > 0) {
          out.add(FoodPortion(label: label, grams: grams));
        }
      }
    }
    return out;
  }

  @override
  String toString() => 'FoodItem($name, ${calories.toStringAsFixed(0)} kcal)';
}
