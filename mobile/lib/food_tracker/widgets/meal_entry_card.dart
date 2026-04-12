import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';
import '../screens/serving_size_screen.dart';

/// Card widget showing a single MealEntry with edit/delete actions.
class MealEntryCard extends StatelessWidget {
  final MealEntry entry;

  const MealEntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(
          entry.foodItem.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${entry.mealType.label}  ·  '
          '${entry.servingGrams.toStringAsFixed(0)} g  ·  '
          '${entry.calories.toStringAsFixed(0)} kcal',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Macro chips
            _MacroChip('P ${entry.protein.toStringAsFixed(1)}g', Colors.blue),
            const SizedBox(width: 4),
            _MacroChip('Fe ${entry.iron.toStringAsFixed(1)}mg', Colors.red[300]!),
            // Actions
            PopupMenuButton<_Action>(
              onSelected: (action) => _onAction(context, action),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _Action.edit, child: Text('Edit serving')),
                const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onAction(BuildContext context, _Action action) {
    if (action == _Action.delete) {
      context.read<FoodTrackerProvider>().deleteEntry(entry.id);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServingSizeScreen(
            food: entry.foodItem,
            initialMultiplier: entry.quantityMultiplier,
            initialMealType: entry.mealType,
            existingEntryId: entry.id,
          ),
        ),
      );
    }
  }
}

enum _Action { edit, delete }

class _MacroChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MacroChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
