import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';
import '../widgets/meal_entry_card.dart';

/// Full-screen list of all meals logged for [date], grouped by MealType.
class MealLogScreen extends StatelessWidget {
  final DateTime date;
  const MealLogScreen({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('EEEE, MMM d').format(date);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Consumer<FoodTrackerProvider>(
        builder: (_, provider, __) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = provider.entries;
          if (entries.isEmpty) {
            return const Center(
              child: Text('No meals logged for this day.', style: TextStyle(color: Colors.grey)),
            );
          }

          // Group by meal type
          final grouped = <MealType, List<MealEntry>>{};
          for (final e in entries) {
            grouped.putIfAbsent(e.mealType, () => []).add(e);
          }

          final orderedTypes = [
            MealType.breakfast,
            MealType.lunch,
            MealType.dinner,
            MealType.snack,
          ].where(grouped.containsKey).toList();

          return ListView(
            children: [
              for (final type in orderedTypes) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    type.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...grouped[type]!.map((e) => MealEntryCard(entry: e)),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}
