import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NutritionResultPage extends StatelessWidget {
  final String? imagePath;
  final String foodName; // user-entered name
  final Map<String, dynamic>? nutrition;

  const NutritionResultPage({
    super.key,
    this.imagePath,
    required this.foodName,
    required this.nutrition,
  });

  double? _getNutrient(String name) {
    final nutrients = nutrition?['foodNutrients'] ?? [];
    for (final n in nutrients) {
      if (n['nutrientName'] == name) {
        return (n['value'] as num?)?.toDouble();
      }
    }
    return null;
  }

  Widget _buildImage() {
    if (imagePath == null || imagePath!.isEmpty) {
      return const SizedBox.shrink();
    }

    if (kIsWeb) {
      return Image.network(imagePath!, height: 200, fit: BoxFit.cover);
    } else {
      return Image.file(File(imagePath!), height: 200, fit: BoxFit.cover);
    }
  }

  @override
  Widget build(BuildContext context) {
    // USDA-provided description
    final apiName = (nutrition?['description'] ?? 'Unknown').toString();

    final calories = _getNutrient('Energy');
    final protein = _getNutrient('Protein');
    final carbs = _getNutrient('Carbohydrate, by difference');
    final fat = _getNutrient('Total lipid (fat)');
    final iron = _getNutrient('Iron, Fe');
    final ironPercent = iron != null ? (iron / 18 * 100) : null;

    return Scaffold(
      appBar: AppBar(title: Text(foodName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImage(),
            const SizedBox(height: 16),

            // Show user-entered and API-returned name
            Text('You entered: $foodName', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text('API returned: $apiName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Text(
              'Calories: ${calories?.toStringAsFixed(1) ?? '--'} kcal'
              '${calories != null ? ' (${(calories / 2000 * 100).toStringAsFixed(0)}%)' : ''}',
            ),
            Text(
              'Protein: ${protein?.toStringAsFixed(1) ?? '--'} g'
              '${protein != null ? ' (${(protein / 50 * 100).toStringAsFixed(0)}%)' : ''}',
            ),
            Text(
              'Carbs: ${carbs?.toStringAsFixed(1) ?? '--'} g'
              '${carbs != null ? ' (${(carbs / 275 * 100).toStringAsFixed(0)}%)' : ''}',
            ),
            Text(
              'Fat: ${fat?.toStringAsFixed(1) ?? '--'} g'
              '${fat != null ? ' (${(fat / 78 * 100).toStringAsFixed(0)}%)' : ''}',
            ),
            const SizedBox(height: 8),
            Text(
              'Iron: ${iron?.toStringAsFixed(1) ?? '--'} mg'
              '${ironPercent != null ? ' (${ironPercent.toStringAsFixed(0)}%)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            if (ironPercent != null) ...[
              const SizedBox(height: 8),
              Text(
                ironPercent >= 20
                    ? 'This food is a good source of iron and may be beneficial for people with iron deficiency or anemia.'
                    : ironPercent >= 10
                        ? 'This food provides a moderate amount of iron and can help support iron intake.'
                        : 'This food is low in iron and may not significantly contribute to daily iron needs.',
                style: TextStyle(
                  color: ironPercent >= 20
                      ? Colors.green
                      : ironPercent >= 10
                          ? Colors.orange
                          : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 24),
            const Text(
              'Percent Daily Values (%DV) are based on FDA guidelines for a '
              '2,000 calorie diet. Reference intakes: Calories 2,000 kcal, '
              'Protein 50 g, Carbohydrates 275 g, Fat 78 g, Iron 18 mg. '
              'Daily values may vary depending on age, sex, and activity level.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}