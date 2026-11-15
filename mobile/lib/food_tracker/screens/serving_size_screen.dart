import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';
import '../services/usda_service.dart';

/// Lets the user choose how much of a food they ate — in household units
/// ("cup", "slice"), label servings, or grams — and the meal type, before
/// saving (new) or updating (existing) a meal entry.
class ServingSizeScreen extends StatefulWidget {
  final FoodItem food;

  /// Multiplier of [FoodItem.servingSize] to start from. Null (new entries)
  /// starts at one of the food's natural portion when it has one.
  final double? initialMultiplier;
  final MealType initialMealType;
  final String? existingEntryId; // null = new entry
  /// When true: pops with the chosen multiplier (double) instead of logging.
  final bool pickerMode;

  const ServingSizeScreen({
    super.key,
    required this.food,
    this.initialMultiplier,
    this.initialMealType = MealType.snack,
    this.existingEntryId,
    this.pickerMode = false,
  });

  @override
  State<ServingSizeScreen> createState() => _ServingSizeScreenState();
}

/// One selectable unit of measure and its weight.
@visibleForTesting
class ServingUnit {
  final String label;
  final double grams;
  const ServingUnit(this.label, this.grams);
}

/// Units offered for [food]: its default serving, any household portions,
/// then plain grams.
@visibleForTesting
List<ServingUnit> servingUnitsFor(FoodItem food) {
  final units = <ServingUnit>[
    food.servingSize == 100
        ? const ServingUnit('100 g', 100)
        : ServingUnit(
            'serving (${_fmtNum(food.servingSize)} g)', food.servingSize),
  ];
  for (final p in food.portions) {
    // "1 cup" reads better as "cup" next to a quantity field.
    final name =
        p.label.startsWith('1 ') ? p.label.substring(2).trim() : p.label;
    final label = name.contains('(') ? name : '$name (${_fmtNum(p.grams)} g)';
    units.add(ServingUnit(label, p.grams));
  }
  units.add(const ServingUnit('g', 1));
  return units;
}

/// Picks the unit and quantity that most naturally express [totalGrams]:
/// the first non-gram unit that divides it into quarter steps, else the
/// default serving.
@visibleForTesting
(int unitIndex, double quantity) bestUnitFor(
  List<ServingUnit> units,
  double totalGrams,
) {
  for (var i = 0; i < units.length - 1; i++) {
    final q = totalGrams / units[i].grams;
    final quarters = q * 4;
    if (q > 0 && (quarters - quarters.round()).abs() < 0.02) {
      return (i, quarters.round() / 4);
    }
  }
  return (0, totalGrams / units.first.grams);
}

String _fmtNum(double v) {
  if ((v - v.roundToDouble()).abs() < 0.005) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

class _ServingSizeScreenState extends State<ServingSizeScreen> {
  late FoodItem _food;
  late List<ServingUnit> _units;
  late int _unitIndex;
  late double _quantity;
  late MealType _mealType;
  late TextEditingController _qtyCtrl;

  bool _touched = false; // user changed amount or unit
  bool _loadingPortions = false;

  @override
  void initState() {
    super.initState();
    _food = widget.food;
    _mealType = widget.initialMealType;
    _qtyCtrl = TextEditingController();
    _resetUnits();
    _maybeFetchPortions();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  /// (Re)builds the unit list and chooses the starting unit + quantity.
  void _resetUnits() {
    _units = servingUnitsFor(_food);
    final initial = widget.initialMultiplier;
    if (initial != null) {
      final (i, q) = bestUnitFor(_units, initial * _food.servingSize);
      _unitIndex = i;
      _quantity = q;
    } else {
      // New entry: one natural portion if we know one, else one serving.
      _unitIndex = _food.portions.isNotEmpty ? 1 : 0;
      _quantity = 1;
    }
    _qtyCtrl.text = _fmtNum(_quantity);
  }

  /// USDA search results omit household measures for non-branded foods, so
  /// fetch them in the background the first time such a food is opened.
  Future<void> _maybeFetchPortions() async {
    if (_food.portions.isNotEmpty || int.tryParse(_food.id) == null) return;

    setState(() => _loadingPortions = true);
    final portions = await UsdaService.fetchPortions(_food.id);
    if (!mounted) return;

    setState(() {
      _loadingPortions = false;
      if (portions.isEmpty) return;
      _food = _food.copyWith(portions: portions);
      if (_touched) {
        // Keep what the user already picked; just add the new options.
        final current = _units[_unitIndex];
        _units = servingUnitsFor(_food);
        final i = _units.indexWhere(
            (u) => u.label == current.label && u.grams == current.grams);
        _unitIndex = i >= 0 ? i : 0;
      } else {
        _resetUnits();
      }
    });
    if (portions.isNotEmpty) {
      context.read<FoodTrackerProvider>().cachePortions(_food);
    }
  }

  // ── Derived values ─────────────────────────────────────────────────────────

  ServingUnit get _unit => _units[_unitIndex];
  double get _grams => _quantity * _unit.grams;
  double get _multiplier => _grams / _food.servingSize;

  double get _calories => _food.calories * _multiplier;
  double get _protein => _food.protein * _multiplier;
  double get _carbs => _food.carbs * _multiplier;
  double get _fat => _food.fat * _multiplier;
  double get _iron => _food.iron * _multiplier;

  bool get _valid => _quantity > 0 && _multiplier <= 99;

  // ── Actions ────────────────────────────────────────────────────────────────

  void _setQuantity(double q) {
    setState(() {
      _touched = true;
      _quantity = q;
      _qtyCtrl.text = _fmtNum(q);
    });
  }

  void _step(int direction) {
    final step = _unit.grams == 1 ? 10.0 : 0.5;
    final next = _quantity + direction * step;
    if (next > 0) _setQuantity(next);
  }

  void _changeUnit(int index) {
    if (index == _unitIndex) return;
    final wasGrams = _unit.grams == 1;
    final toGrams = _units[index].grams == 1;
    setState(() {
      _touched = true;
      // Converting to/from grams keeps the same amount of food; switching
      // between named units keeps the count ("2 slices" → "2 cups").
      if (toGrams) {
        _quantity = _grams.roundToDouble();
      } else if (wasGrams) {
        _quantity = 1;
      }
      _unitIndex = index;
      _qtyCtrl.text = _fmtNum(_quantity);
    });
  }

  Future<void> _save() async {
    if (!_valid) return;

    if (widget.pickerMode) {
      Navigator.of(context).pop(_multiplier);
      return;
    }

    final provider = context.read<FoodTrackerProvider>();

    if (widget.existingEntryId != null) {
      await provider.updateEntry(
        widget.existingEntryId!,
        multiplier: _multiplier,
        mealType: _mealType,
      );
    } else {
      await provider.addEntry(
        food: _food,
        multiplier: _multiplier,
        mealType: _mealType,
      );
    }

    if (mounted) {
      Navigator.of(context).popUntil(
          (r) => r.isFirst || r.settings.name == '/food_tracker');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingEntryId != null;
    final title = widget.pickerMode
        ? 'Set Serving'
        : (isEdit ? 'Edit Serving' : 'Adjust Serving');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Food name
          Text(
            _food.name,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
          ),
          if (_food.brand != null)
            Text(_food.brand!, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          // Amount + unit
          const Text('Amount', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(
                icon: const Icon(Icons.remove),
                tooltip: 'Less',
                onPressed: () => _step(-1),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _qtyCtrl,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v.replaceAll(',', '.'));
                    setState(() {
                      _touched = true;
                      _quantity = parsed != null && parsed > 0 ? parsed : 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                icon: const Icon(Icons.add),
                tooltip: 'More',
                onPressed: () => _step(1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _unitIndex,
                      isExpanded: true,
                      items: [
                        for (var i = 0; i < _units.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              _units[i].label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (i) {
                        if (i != null) _changeUnit(i);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _loadingPortions
                ? 'Loading more units…'
                : _multiplier > 99
                    ? 'That amount is too large to log.'
                    : '= ${_fmtNum(_grams.roundToDouble())} g',
            style: TextStyle(
              fontSize: 13,
              color: _multiplier > 99 ? Colors.red : Colors.grey,
            ),
          ),
          const SizedBox(height: 20),

          // Meal type selector (hidden in picker mode)
          if (!widget.pickerMode) ...[
            const Text('Meal type',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: MealType.values.map((t) {
                final selected = _mealType == t;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _mealType = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Live nutrient preview
          const Divider(),
          const Text(
            'Nutrition preview',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _NutrientRow('Calories', _calories, 'kcal'),
          _NutrientRow('Protein', _protein, 'g'),
          _NutrientRow('Carbs', _carbs, 'g'),
          _NutrientRow('Fat', _fat, 'g'),
          _NutrientRow('Iron', _iron, 'mg'),
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: ElevatedButton(
          onPressed: _valid ? _save : null,
          child: Text(
            widget.pickerMode
                ? 'Add to Meal'
                : (isEdit ? 'Save Changes' : 'Add to Log'),
          ),
        ),
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  const _NutrientRow(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('${value.toStringAsFixed(1)} $unit'),
        ],
      ),
    );
  }
}
