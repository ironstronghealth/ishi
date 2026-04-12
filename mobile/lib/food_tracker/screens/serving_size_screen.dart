import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';

/// Allows the user to adjust serving size (multiplier) and meal type
/// before saving (new) or updating (existing) a meal entry.
class ServingSizeScreen extends StatefulWidget {
  final FoodItem food;
  final double initialMultiplier;
  final MealType initialMealType;
  final String? existingEntryId; // null = new entry

  const ServingSizeScreen({
    super.key,
    required this.food,
    this.initialMultiplier = 1.0,
    this.initialMealType = MealType.snack,
    this.existingEntryId,
  });

  @override
  State<ServingSizeScreen> createState() => _ServingSizeScreenState();
}

class _ServingSizeScreenState extends State<ServingSizeScreen> {
  late double _multiplier;
  late MealType _mealType;
  late TextEditingController _multCtrl;

  @override
  void initState() {
    super.initState();
    _multiplier = widget.initialMultiplier;
    _mealType = widget.initialMealType;
    _multCtrl =
        TextEditingController(text: _multiplier.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _multCtrl.dispose();
    super.dispose();
  }

  // ── Derived values ─────────────────────────────────────────────────────────

  double get _calories => widget.food.calories * _multiplier;
  double get _protein => widget.food.protein * _multiplier;
  double get _carbs => widget.food.carbs * _multiplier;
  double get _fat => widget.food.fat * _multiplier;
  double get _iron => widget.food.iron * _multiplier;
  double get _grams => widget.food.servingSize * _multiplier;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final provider = context.read<FoodTrackerProvider>();

    if (widget.existingEntryId != null) {
      await provider.updateEntry(
        widget.existingEntryId!,
        multiplier: _multiplier,
        mealType: _mealType,
      );
    } else {
      await provider.addEntry(
        food: widget.food,
        multiplier: _multiplier,
        mealType: _mealType,
      );
    }

    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/food_tracker');
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingEntryId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Serving' : 'Adjust Serving'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Food name
          Text(
            widget.food.name,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
          ),
          if (widget.food.brand != null)
            Text(widget.food.brand!, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          // Serving size multiplier
          Text(
            'Serving size: ${widget.food.servingSize.toStringAsFixed(0)} g × multiplier = ${_grams.toStringAsFixed(0)} g',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _multiplier.clamp(0.1, 5.0),
                  min: 0.1,
                  max: 5.0,
                  divisions: 49,
                  label: _multiplier.toStringAsFixed(2),
                  onChanged: (v) => setState(() {
                    _multiplier = v;
                    _multCtrl.text = v.toStringAsFixed(2);
                  }),
                ),
              ),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _multCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '×',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      setState(() => _multiplier = parsed.clamp(0.1, 99.0));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Meal type selector
          const Text('Meal type', style: TextStyle(fontWeight: FontWeight.w500)),
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
          onPressed: _save,
          child: Text(isEdit ? 'Save Changes' : 'Add to Log'),
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
