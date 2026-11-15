import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';
import 'barcode_scan_screen.dart';
import 'custom_food_screen.dart';
import 'serving_size_screen.dart';

/// Full-screen food picker: USDA search, barcode scan, and — before the user
/// types anything — their recent, frequent, favourite and custom foods.
class FoodSearchScreen extends StatefulWidget {
  /// When provided, the scan result is pre-filled in the search box.
  final String? prefilledQuery;

  /// When set, the screen runs in "picker" mode: after the user adjusts the
  /// serving size the callback is invoked and both screens are popped.
  /// When null, the selected food is logged normally via [ServingSizeScreen].
  final void Function(FoodItem food, double multiplier)? onFoodPicked;

  const FoodSearchScreen({
    super.key,
    this.prefilledQuery,
    this.onFoodPicked,
  });

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

enum _LibraryTab {
  recent('Recent'),
  frequent('Frequent'),
  favorites('Favourites'),
  custom('My Foods');

  final String label;
  const _LibraryTab(this.label);
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  late TextEditingController _searchCtrl;
  _LibraryTab _tab = _LibraryTab.recent;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.prefilledQuery ?? '');
    // Rebuild when the box is cleared so the library lists come back.
    _searchCtrl.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<FoodTrackerProvider>();
      provider.loadFoodLibrary();
      if (widget.prefilledQuery != null && widget.prefilledQuery!.isNotEmpty) {
        // Auto-search if arrived from scan
        provider.searchFood(widget.prefilledQuery!);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _queryWasEmpty = true;

  void _onQueryChanged() {
    final empty = _searchCtrl.text.trim().isEmpty;
    if (empty != _queryWasEmpty) setState(() => _queryWasEmpty = empty);
  }

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    context.read<FoodTrackerProvider>().searchFood(q);
  }

  /// Live barcode scanning needs a camera; only offer it on phones/tablets.
  bool get _canScanBarcode =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Scans a package barcode and jumps straight to the serving-size step
  /// for the matched product.
  Future<void> _scanBarcode() async {
    final food = await Navigator.push<FoodItem>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (food != null && mounted) _selectFood(context, food);
  }

  /// Opens the custom-food form; a newly created food goes straight to the
  /// serving-size step.
  Future<void> _createFood() async {
    final food = await Navigator.push<FoodItem>(
      context,
      MaterialPageRoute(builder: (_) => const CustomFoodScreen()),
    );
    if (food != null && mounted) _selectFood(context, food);
  }

  Future<void> _editFood(FoodItem food) async {
    await Navigator.push<FoodItem>(
      context,
      MaterialPageRoute(builder: (_) => CustomFoodScreen(existing: food)),
    );
  }

  Future<void> _deleteFood(FoodItem food) async {
    final provider = context.read<FoodTrackerProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete food?'),
        content: Text(
          '"${food.name}" will be removed from your foods. '
          'Meals you already logged are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await provider.removeFromLibrary(food.id);
  }

  void _selectFood(BuildContext context, FoodItem food) {
    if (widget.onFoodPicked != null) {
      // Picker mode: capture the navigator before pushing so we can pop this
      // screen after the user confirms the serving size.
      final nav = Navigator.of(context);
      Navigator.push<double>(
        context,
        MaterialPageRoute(
          builder: (_) => ServingSizeScreen(
            food: food,
            initialMealType: MealType.snack,
            pickerMode: true,
          ),
        ),
      ).then((multiplier) {
        if (multiplier != null) {
          widget.onFoodPicked!(food, multiplier);
          nav.pop();
        }
      });
      return;
    }

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
      appBar: AppBar(
        title: Text(
            widget.onFoodPicked != null ? 'Add Food to Meal' : 'Search Food'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create a food',
            onPressed: _createFood,
          ),
        ],
      ),
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
                      suffixIcon: _queryWasEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear',
                              onPressed: _searchCtrl.clear,
                            ),
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
                if (_canScanBarcode)
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan barcode',
                    onPressed: _scanBarcode,
                  ),
              ],
            ),
          ),

          // ── Library (empty query) or search results ────────────────────────
          Expanded(
            child: Consumer<FoodTrackerProvider>(
              builder: (_, provider, __) {
                if (provider.isSearching) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_queryWasEmpty) return _buildLibrary(provider);

                if (provider.searchError != null &&
                    provider.searchResults.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off,
                              size: 48, color: Colors.grey),
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
                          TextButton.icon(
                            onPressed: _createFood,
                            icon: const Icon(Icons.add),
                            label: const Text('Create this food yourself'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (provider.searchResults.isEmpty) {
                  return const Center(
                    child: Text(
                      'Press Go to search the USDA food database.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return _foodList(provider, provider.searchResults);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Library view ───────────────────────────────────────────────────────────

  Widget _buildLibrary(FoodTrackerProvider provider) {
    final foods = switch (_tab) {
      _LibraryTab.recent => provider.recentFoods,
      _LibraryTab.frequent => provider.frequentFoods,
      _LibraryTab.favorites => provider.favoriteFoods,
      _LibraryTab.custom => provider.customFoods,
    };

    final emptyText = switch (_tab) {
      _LibraryTab.recent => 'Foods you log will show up here.',
      _LibraryTab.frequent =>
        'Foods you log more than once will show up here.',
      _LibraryTab.favorites => 'Tap the star on any food to keep it here.',
      _LibraryTab.custom =>
        'Foods you create from a nutrition label will show up here.',
    };

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final tab in _LibraryTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tab.label),
                    selected: _tab == tab,
                    onSelected: (_) => setState(() => _tab = tab),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: foods.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        if (_tab == _LibraryTab.custom) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _createFood,
                            icon: const Icon(Icons.add),
                            label: const Text('Create a food'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : _foodList(
                  provider,
                  foods,
                  manageCustom: _tab == _LibraryTab.custom,
                ),
        ),
      ],
    );
  }

  // ── Shared food list ───────────────────────────────────────────────────────

  Widget _foodList(
    FoodTrackerProvider provider,
    List<FoodItem> foods, {
    bool manageCustom = false,
  }) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: foods.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (_, i) {
        final food = foods[i];
        final starred = provider.isFavorite(food.id);
        final basis = food.servingSize == 100
            ? 'per 100 g'
            : 'per ${food.servingSize.toStringAsFixed(0)} g serving';
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          title: Text(food.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${food.calories.toStringAsFixed(0)} kcal'
            '  ·  P ${food.protein.toStringAsFixed(1)}g'
            '  ·  Fe ${food.iron.toStringAsFixed(1)}mg'
            '  ·  $basis'
            '${food.brand != null ? '\n${food.brand}' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          isThreeLine: food.brand != null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  starred ? Icons.star : Icons.star_border,
                  color: starred ? Colors.amber[700] : null,
                ),
                tooltip:
                    starred ? 'Remove from favourites' : 'Add to favourites',
                onPressed: () => provider.toggleFavorite(food),
              ),
              if (manageCustom)
                PopupMenuButton<String>(
                  onSelected: (action) => action == 'edit'
                      ? _editFood(food)
                      : _deleteFood(food),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          onTap: () => _selectFood(context, food),
        );
      },
    );
  }
}
