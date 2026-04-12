import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';
import 'serving_size_screen.dart';

/// Full-screen food search (USDA API) + optional camera scan entry point.
/// Camera scan is only shown on mobile platforms.
class FoodSearchScreen extends StatefulWidget {
  /// When provided, the scan result is pre-filled in the search box.
  final String? prefilledQuery;

  const FoodSearchScreen({super.key, this.prefilledQuery});

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.prefilledQuery ?? '');
    if (widget.prefilledQuery != null && widget.prefilledQuery!.isNotEmpty) {
      // Auto-search if arrived from scan
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<FoodTrackerProvider>().searchFood(widget.prefilledQuery!);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    context.read<FoodTrackerProvider>().searchFood(q);
  }

  void _selectFood(BuildContext context, FoodItem food) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServingSizeScreen(
          food: food,
          initialMealType: MealType.snack,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Food')),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search food (e.g. "chicken breast")',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _runSearch,
                  child: const Text('Go'),
                ),
              ],
            ),
          ),

          // ── Results ────────────────────────────────────────────────────────
          Expanded(
            child: Consumer<FoodTrackerProvider>(
              builder: (_, provider, __) {
                if (provider.isSearching) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.searchError != null &&
                    provider.searchResults.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            provider.searchError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _runSearch,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (provider.searchResults.isEmpty) {
                  return const Center(
                    child: Text(
                      'Search the USDA food database above.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: provider.searchResults.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (_, i) {
                    final food = provider.searchResults[i];
                    return ListTile(
                      title: Text(food.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${food.calories.toStringAsFixed(0)} kcal'
                        '  ·  P ${food.protein.toStringAsFixed(1)}g'
                        '  ·  Fe ${food.iron.toStringAsFixed(1)}mg'
                        '${food.brand != null ? '\n${food.brand}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      isThreeLine: food.brand != null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _selectFood(context, food),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
