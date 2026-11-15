import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';
import '../services/vision_service.dart';
import 'food_search_screen.dart';

/// Shown after camera scan + Gemini identification.
/// Lets the user review/tweak the AI result before logging.
class FoodConfirmScreen extends StatefulWidget {
  final FoodScanResult scanResult;
  final FoodItem? foodItem; // null if USDA returned no results
  final String imagePath;

  const FoodConfirmScreen({
    super.key,
    required this.scanResult,
    required this.foodItem,
    required this.imagePath,
  });

  @override
  State<FoodConfirmScreen> createState() => _FoodConfirmScreenState();
}

class _FoodConfirmScreenState extends State<FoodConfirmScreen> {
  late double _grams;
  late MealType _mealType;
  late TextEditingController _gramsCtrl;

  FoodItem? get _food => widget.foodItem;

  @override
  void initState() {
    super.initState();
    _grams = widget.scanResult.estimatedGrams.clamp(1.0, 2000.0);
    _mealType = widget.scanResult.suggestedMealType;
    _gramsCtrl = TextEditingController(text: _grams.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _gramsCtrl.dispose();
    super.dispose();
  }

  // Multiplier relative to the USDA 100 g serving baseline
  double get _multiplier =>
      _food != null ? _grams / _food!.servingSize : 1.0;

  double get _calories => (_food?.calories ?? 0) * _multiplier;
  double get _protein => (_food?.protein ?? 0) * _multiplier;
  double get _carbs => (_food?.carbs ?? 0) * _multiplier;
  double get _fat => (_food?.fat ?? 0) * _multiplier;
  double get _iron => (_food?.iron ?? 0) * _multiplier;

  Future<void> _addToLog() async {
    if (_food == null) return;
    await context.read<FoodTrackerProvider>().addEntry(
          food: _food!,
          multiplier: _multiplier,
          mealType: _mealType,
        );
    if (mounted) {
      Navigator.of(context)
          .popUntil((r) => r.isFirst || r.settings.name == '/food_tracker');
    }
  }

  void _searchDifferently() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FoodSearchScreen(prefilledQuery: widget.scanResult.searchQuery),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Food')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Image + AI description ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(widget.imagePath),
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.scanResult.description,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI confidence: ${(widget.scanResult.confidence * 100).toStringAsFixed(0)}%',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Matched USDA food card ─────────────────────────────────────────
          const Text('Matched food',
              style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          if (_food != null)
            Card(
              child: ListTile(
                title: Text(_food!.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle:
                    _food!.brand != null ? Text(_food!.brand!) : null,
                trailing: TextButton(
                  onPressed: _searchDifferently,
                  child: const Text('Change'),
                ),
              ),
            )
          else
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.warning_amber,
                    color: theme.colorScheme.onErrorContainer),
                title: Text('No USDA match found',
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
                subtitle: Text('Search manually to log this food',
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ),

          if (_food == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Search food manually'),
                onPressed: _searchDifferently,
              ),
            ),
          ],

          if (_food != null) ...[
            const SizedBox(height: 20),

            // ── Grams input ────────────────────────────────────────────────
            const Text('Amount',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _gramsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                suffixText: 'g',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                helperText: 'Estimated by AI — adjust if needed',
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null && parsed > 0) {
                  setState(() => _grams = parsed.clamp(1.0, 2000.0));
                }
              },
            ),
            const SizedBox(height: 20),

            // ── Meal type ──────────────────────────────────────────────────
            const Text('Meal type',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: MealType.values
                  .map((t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _mealType == t,
                        onSelected: (_) => setState(() => _mealType = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),

            // ── Nutrition preview ──────────────────────────────────────────
            const Divider(),
            const Text('Nutrition preview',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _NutrientRow('Calories', _calories, 'kcal'),
            _NutrientRow('Protein', _protein, 'g'),
            _NutrientRow('Carbs', _carbs, 'g'),
            _NutrientRow('Fat', _fat, 'g'),
            _NutrientRow('Iron', _iron, 'mg'),
            const SizedBox(height: 80),
          ],
        ],
      ),

      // ── Add to Log button ────────────────────────────────────────────────
      bottomNavigationBar: _food != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: ElevatedButton(
                onPressed: _addToLog,
                child: const Text('Add to Log'),
              ),
            )
          : null,
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
