import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal_entry.dart';
import '../models/saved_meal.dart';
import '../providers/food_tracker_provider.dart';
import 'create_meal_screen.dart';

/// Lists all saved meal templates. Allows logging, editing, and deleting.
class SavedMealsScreen extends StatefulWidget {
  const SavedMealsScreen({super.key});

  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FoodTrackerProvider>().loadSavedMeals();
    });
  }

  // ── Log a meal ─────────────────────────────────────────────────────────────

  Future<void> _logMeal(SavedMeal meal) async {
    // Capture all context-dependent references before any async gap.
    final provider = context.read<FoodTrackerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final mealType = await _pickMealType();
    if (mealType == null || !mounted) return;

    await provider.logSavedMeal(meal, mealType);

    messenger.showSnackBar(
      SnackBar(content: Text('"${meal.name}" logged as ${mealType.label}.')),
    );
    nav.pop();
  }

  Future<MealType?> _pickMealType() {
    return showModalBottomSheet<MealType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Log as…',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            ...MealType.values.map(
              (t) => ListTile(
                leading: Icon(_mealTypeIcon(t)),
                title: Text(t.label),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(SavedMeal meal) async {
    // Capture provider reference before async gap.
    final provider = context.read<FoodTrackerProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete meal?'),
        content: Text('Remove "${meal.name}" from saved meals?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await provider.deleteSavedMeal(meal.id);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Meals'),
      ),
      body: Consumer<FoodTrackerProvider>(
        builder: (_, provider, __) {
          final meals = provider.savedMeals;

          if (meals.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restaurant_menu, size: 56, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No saved meals yet.\nCreate one to log your favourite meals instantly.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Meal'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: meals.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) => _MealCard(
              meal: meals[i],
              onLog: () => _logMeal(meals[i]),
              onEdit: () => _openEdit(meals[i]),
              onDelete: () => _confirmDelete(meals[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        tooltip: 'Create saved meal',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateMealScreen()),
    );
  }

  void _openEdit(SavedMeal meal) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateMealScreen(existingMeal: meal)),
    );
  }
}

// ── Meal list card ─────────────────────────────────────────────────────────

class _MealCard extends StatelessWidget {
  final SavedMeal meal;
  final VoidCallback onLog;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MealCard({
    required this.meal,
    required this.onLog,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(meal.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // deletion is handled by onDelete; don't auto-remove
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          meal.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${meal.items.length} item${meal.items.length == 1 ? '' : 's'}  ·  '
          '${meal.totalCalories.toStringAsFixed(0)} kcal  ·  '
          'P ${meal.totalProtein.toStringAsFixed(1)} g  ·  '
          'Fe ${meal.totalIron.toStringAsFixed(1)} mg',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
            FilledButton(
              onPressed: onLog,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Log'),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _mealTypeIcon(MealType t) {
  switch (t) {
    case MealType.breakfast:
      return Icons.wb_sunny_outlined;
    case MealType.lunch:
      return Icons.lunch_dining_outlined;
    case MealType.dinner:
      return Icons.dinner_dining_outlined;
    case MealType.snack:
      return Icons.cookie_outlined;
  }
}
