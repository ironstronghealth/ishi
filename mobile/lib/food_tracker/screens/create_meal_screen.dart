import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/food_item.dart';
import '../models/saved_meal.dart';
import '../providers/food_tracker_provider.dart';
import 'food_search_screen.dart';

/// Screen for creating or editing a saved meal template.
class CreateMealScreen extends StatefulWidget {
  /// Pass an existing meal to open in edit mode.
  final SavedMeal? existingMeal;

  const CreateMealScreen({super.key, this.existingMeal});

  @override
  State<CreateMealScreen> createState() => _CreateMealScreenState();
}

class _CreateMealScreenState extends State<CreateMealScreen> {
  static const _uuid = Uuid();

  late TextEditingController _nameCtrl;
  late List<SavedMealItem> _items;

  bool get _isEdit => widget.existingMeal != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existingMeal?.name ?? '');
    _items = List.of(widget.existingMeal?.items ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Derived totals ─────────────────────────────────────────────────────────

  double get _totalCalories => _items.fold(0.0, (s, i) => s + i.calories);
  double get _totalProtein => _items.fold(0.0, (s, i) => s + i.protein);
  double get _totalCarbs => _items.fold(0.0, (s, i) => s + i.carbs);
  double get _totalFat => _items.fold(0.0, (s, i) => s + i.fat);
  double get _totalIron => _items.fold(0.0, (s, i) => s + i.iron);

  // ── Actions ────────────────────────────────────────────────────────────────

  void _addFood(BuildContext context) {
    context.read<FoodTrackerProvider>().clearSearch();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          onFoodPicked: (FoodItem food, double multiplier) {
            setState(() {
              _items.add(SavedMealItem(
                foodItem: food,
                quantityMultiplier: multiplier,
              ));
            });
          },
        ),
      ),
    );
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give this meal a name.')),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one food item.')),
      );
      return;
    }

    final meal = SavedMeal(
      id: widget.existingMeal?.id ?? _uuid.v4(),
      name: name,
      items: List.of(_items),
    );
    await context.read<FoodTrackerProvider>().upsertSavedMeal(meal);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Meal' : 'New Saved Meal'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Name field ───────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Meal name',
              hintText: 'e.g. Chicken Sandwich',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),

          // ── Food items ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Foods (${_items.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              TextButton.icon(
                onPressed: () => _addFood(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Food'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No foods added yet.\nTap "Add Food" to search the USDA database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._items.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    item.foodItem.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.grams.toStringAsFixed(0)} g  ·  '
                    '${item.calories.toStringAsFixed(0)} kcal  ·  '
                    'P ${item.protein.toStringAsFixed(1)} g  ·  '
                    'Fe ${item.iron.toStringAsFixed(1)} mg',
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: false,
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () => _removeItem(idx),
                  ),
                ),
              );
            }),

          // ── Totals summary ───────────────────────────────────────────────
          if (_items.isNotEmpty) ...[
            const Divider(height: 32),
            Text(
              'Meal totals',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _TotalRow('Calories', _totalCalories, 'kcal'),
            _TotalRow('Protein', _totalProtein, 'g'),
            _TotalRow('Carbs', _totalCarbs, 'g'),
            _TotalRow('Fat', _totalFat, 'g'),
            _TotalRow('Iron', _totalIron, 'mg'),
          ],

          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const Text('Save Meal'),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  const _TotalRow(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '${value.toStringAsFixed(1)} $unit',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
