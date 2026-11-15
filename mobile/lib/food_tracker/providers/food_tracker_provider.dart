import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/food_item.dart';
import '../models/library_food.dart';
import '../models/meal_entry.dart';
import '../models/nutrition_goals.dart';
import '../models/saved_meal.dart';
import '../services/meal_storage.dart';
import '../services/usda_service.dart';

/// Central state manager for the food tracker feature.
/// Consumed via Provider in all food-tracker screens.
class FoodTrackerProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  // ── State ──────────────────────────────────────────────────────────────────

  DateTime _selectedDate = _today();
  List<MealEntry> _entries = [];
  NutritionGoals _goals = const NutritionGoals();

  // Search state
  List<FoodItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  // Saved meal templates
  List<SavedMeal> _savedMeals = [];
  bool _savedMealsLoaded = false;

  // Weekly data (last 7 days, keyed by YYYY-MM-DD)
  Map<String, List<MealEntry>> _weeklyEntries = {};
  bool _weeklyLoaded = false;

  bool _isLoading = false;
  int _loadGeneration = 0; // incremented on every loadEntriesForDate call

  // Per-date entry cache (keyed by YYYY-MM-DD).
  // On web (no SQLite) this is the only persistence layer, so entries must
  // survive date navigation. On native it avoids redundant DB reads.
  final Map<String, List<MealEntry>> _entriesCache = {};

  // ── Public getters ─────────────────────────────────────────────────────────

  DateTime get selectedDate => _selectedDate;
  List<MealEntry> get entries => List.unmodifiable(_entries);
  NutritionGoals get goals => _goals;

  List<FoodItem> get searchResults => List.unmodifiable(_searchResults);
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  List<SavedMeal> get savedMeals => List.unmodifiable(_savedMeals);

  Map<String, List<MealEntry>> get weeklyEntries => _weeklyEntries;
  bool get weeklyLoaded => _weeklyLoaded;
  bool get isLoading => _isLoading;

  // ── Aggregated daily totals ────────────────────────────────────────────────

  double get totalCalories => _sum((e) => e.calories);
  double get totalProtein => _sum((e) => e.protein);
  double get totalCarbs => _sum((e) => e.carbs);
  double get totalFat => _sum((e) => e.fat);
  double get totalIron => _sum((e) => e.iron);

  double _sum(double Function(MealEntry) fn) =>
      _entries.fold(0.0, (acc, e) => acc + fn(e));

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _goals = await NutritionGoals.load();
    await loadFoodLibrary();
    await loadEntriesForDate(_selectedDate);
  }

  // ── Date navigation ────────────────────────────────────────────────────────

  Future<void> selectDate(DateTime date) async {
    _selectedDate = date;
    notifyListeners();
    await loadEntriesForDate(date);
  }

  Future<void> loadEntriesForDate(DateTime date) async {
    final key = _fmtDate(date);
    // Always increment so any in-flight DB load for a previous navigation is
    // invalidated and won't overwrite the result of this (newer) call.
    final gen = ++_loadGeneration;

    // Serve from in-memory cache when available (covers web where SQLite is
    // absent AND native where the date was already loaded this session).
    if (kIsWeb || _entriesCache.containsKey(key)) {
      _entries = List.of(_entriesCache[key] ?? []);
      notifyListeners();
      return;
    }

    // First time seeing this date on native — query SQLite.
    _isLoading = true;
    notifyListeners();
    try {
      final entries = await MealStorage.entriesForDate(date);
      // Cache regardless of staleness so the query cost isn't wasted.
      _entriesCache[key] = entries;
      if (gen != _loadGeneration) return; // a newer load started — discard
      _entries = entries;
    } finally {
      if (gen == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Add a new meal entry.
  Future<void> addEntry({
    required FoodItem food,
    required double multiplier,
    required MealType mealType,
  }) async {
    // Use the selected date so entries logged while viewing a past day are
    // saved to that day, not today.
    final now = DateTime.now();
    final timestamp = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );
    final entry = MealEntry(
      id: _uuid.v4(),
      foodItem: food,
      quantityMultiplier: multiplier,
      timestamp: timestamp,
      mealType: mealType,
    );

    if (!kIsWeb) {
      await MealStorage.saveMeal(entry);
    }
    await _recordFoodUse(food);

    // Keep the per-date cache in sync.
    final key = _fmtDate(entry.timestamp);
    _entriesCache[key] = [...(_entriesCache[key] ?? []), entry];

    // Also update the active list when the entry belongs to the selected date.
    if (_isSameDay(entry.timestamp, _selectedDate)) {
      _entries = [..._entries, entry];
    }
    _weeklyLoaded = false; // invalidate weekly cache
    notifyListeners();
  }

  /// Update an existing entry's multiplier/mealType.
  Future<void> updateEntry(
    String id, {
    required double multiplier,
    required MealType mealType,
  }) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx == -1) return;

    final updated = _entries[idx].copyWith(
      quantityMultiplier: multiplier,
      mealType: mealType,
    );

    if (!kIsWeb) {
      await MealStorage.saveMeal(updated);
    }

    // Keep the per-date cache in sync.
    final key = _fmtDate(updated.timestamp);
    if (_entriesCache.containsKey(key)) {
      final ci = _entriesCache[key]!.indexWhere((e) => e.id == id);
      if (ci >= 0) {
        _entriesCache[key] = [..._entriesCache[key]!]..[ci] = updated;
      }
    }

    _entries = [..._entries]..[idx] = updated;
    _weeklyLoaded = false;
    notifyListeners();
  }

  /// Delete a meal entry.
  Future<void> deleteEntry(String id) async {
    if (!kIsWeb) {
      await MealStorage.deleteMeal(id);
    }

    // Keep the per-date cache in sync.
    for (final key in _entriesCache.keys.toList()) {
      final list = _entriesCache[key]!;
      final ci = list.indexWhere((e) => e.id == id);
      if (ci >= 0) {
        _entriesCache[key] = [...list]..removeAt(ci);
        break; // IDs are unique across dates
      }
    }

    _entries = _entries.where((e) => e.id != id).toList();
    _weeklyLoaded = false;
    notifyListeners();
  }

  // ── Copy from another day ──────────────────────────────────────────────────

  /// Entries logged on [date], without changing the selected date.
  Future<List<MealEntry>> entriesOn(DateTime date) async {
    final key = _fmtDate(date);
    final cached = _entriesCache[key];
    if (cached != null || kIsWeb) return List.of(cached ?? const []);
    final entries = await MealStorage.entriesForDate(date);
    _entriesCache[key] = entries;
    return List.of(entries);
  }

  /// Re-logs [source] entries onto the currently selected date, keeping each
  /// one's serving and meal type.
  Future<void> copyEntriesToSelectedDate(List<MealEntry> source) async {
    for (final e in source) {
      await addEntry(
        food: e.foodItem,
        multiplier: e.quantityMultiplier,
        mealType: e.mealType,
      );
    }
  }

  // ── Food library: recents, frequent, favourites, custom foods ──────────────

  static const _libraryListLimit = 30;

  final Map<String, LibraryFood> _library = {};
  bool _libraryLoaded = false;

  Future<void> loadFoodLibrary() async {
    if (_libraryLoaded) return;
    _libraryLoaded = true;
    if (!kIsWeb) {
      try {
        for (final f in await MealStorage.loadFoodLibrary()) {
          _library[f.food.id] = f;
        }
      } catch (e) {
        debugPrint('Food library load failed: $e');
      }
    }
    notifyListeners();
  }

  /// Most recently logged foods, newest first.
  List<FoodItem> get recentFoods {
    final used = _library.values.where((f) => f.lastUsedAt != null).toList()
      ..sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
    return used.take(_libraryListLimit).map((f) => f.food).toList();
  }

  /// Foods logged more than once, most-logged first.
  List<FoodItem> get frequentFoods {
    final used = _library.values.where((f) => f.useCount >= 2).toList()
      ..sort((a, b) {
        final byCount = b.useCount.compareTo(a.useCount);
        if (byCount != 0) return byCount;
        return (b.lastUsedAt ?? DateTime(0))
            .compareTo(a.lastUsedAt ?? DateTime(0));
      });
    return used.take(_libraryListLimit).map((f) => f.food).toList();
  }

  List<FoodItem> get favoriteFoods => _sortedByName((f) => f.isFavorite);
  List<FoodItem> get customFoods => _sortedByName((f) => f.isCustom);

  List<FoodItem> _sortedByName(bool Function(LibraryFood) test) {
    final list = _library.values.where(test).map((f) => f.food).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  bool isFavorite(String foodId) => _library[foodId]?.isFavorite ?? false;
  bool isCustomFood(String foodId) => _library[foodId]?.isCustom ?? false;
  String? barcodeFor(String foodId) => _library[foodId]?.barcode;

  /// A food previously scanned or saved against [barcode], if any.
  FoodItem? foodForBarcode(String barcode) {
    final wanted = _normBarcode(barcode);
    for (final f in _library.values) {
      if (f.barcode != null && _normBarcode(f.barcode!) == wanted) {
        return f.food;
      }
    }
    return null;
  }

  Future<void> toggleFavorite(FoodItem food) async {
    final existing = _library[food.id];
    final updated = (existing ?? LibraryFood(food: food))
        .copyWith(isFavorite: !(existing?.isFavorite ?? false));
    await _putLibraryFood(updated);
  }

  /// Creates or updates a user-entered food. When [barcode] is given, future
  /// scans of that code resolve to this food; null clears any stored code.
  Future<void> saveCustomFood(FoodItem food, {String? barcode}) async {
    final existing = _library[food.id];
    await _putLibraryFood(LibraryFood(
      food: food,
      isFavorite: existing?.isFavorite ?? false,
      isCustom: true,
      barcode: barcode,
      useCount: existing?.useCount ?? 0,
      lastUsedAt: existing?.lastUsedAt,
    ));
  }

  /// Remembers which product a barcode resolved to so the next scan is
  /// instant and works offline.
  Future<void> rememberBarcode(FoodItem food, String barcode) async {
    final existing = _library[food.id];
    await _putLibraryFood(
      (existing ?? LibraryFood(food: food)).copyWith(barcode: barcode),
    );
  }

  /// Removes a food from every library list. Already-logged meals keep their
  /// own copy of the food and are unaffected.
  Future<void> removeFromLibrary(String foodId) async {
    if (_library.remove(foodId) == null) return;
    if (!kIsWeb) await MealStorage.deleteLibraryFood(foodId);
    notifyListeners();
  }

  /// Stores portions fetched on demand so they don't need re-fetching.
  Future<void> cachePortions(FoodItem food) async {
    final existing = _library[food.id];
    if (existing == null) return;
    await _putLibraryFood(existing.copyWith(food: food), notify: false);
  }

  Future<void> _recordFoodUse(FoodItem food) async {
    final existing = _library[food.id];
    // Keep richer stored data (e.g. cached portions) if this copy lacks it.
    final merged = food.portions.isEmpty && existing != null
        ? food.copyWith(portions: existing.food.portions)
        : food;
    await _putLibraryFood(
      (existing ?? LibraryFood(food: merged)).copyWith(
        food: merged,
        useCount: (existing?.useCount ?? 0) + 1,
        lastUsedAt: DateTime.now(),
      ),
      notify: false, // callers notify once their own state is updated
    );
  }

  Future<void> _putLibraryFood(LibraryFood f, {bool notify = true}) async {
    if (f.isWorthKeeping) {
      _library[f.food.id] = f;
      if (!kIsWeb) await MealStorage.upsertLibraryFood(f);
    } else {
      _library.remove(f.food.id);
      if (!kIsWeb) await MealStorage.deleteLibraryFood(f.food.id);
    }
    if (notify) notifyListeners();
  }

  // UPC-A and EAN-13 differ only by leading zeros.
  static String _normBarcode(String code) =>
      code.trim().replaceFirst(RegExp(r'^0+'), '');

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<void> searchFood(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _searchError = null;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final results = await UsdaService.search(query);
      _searchResults = results;
      _searchError = results.isEmpty ? 'No results found for "$query".' : null;
    } on TimeoutException {
      _searchResults = [];
      _searchError = 'Request timed out. Check your connection and try again.';
    } catch (e) {
      _searchResults = [];
      _searchError = 'Search failed. Check your connection and try again.';
      debugPrint('USDA search exception: $e');
    } finally {
      _isSearching = false;
    }
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }

  // ── Goals ──────────────────────────────────────────────────────────────────

  Future<void> updateGoals(NutritionGoals goals) async {
    _goals = goals;
    await goals.save();
    notifyListeners();
  }

  // ── Saved meals ────────────────────────────────────────────────────────────

  Future<void> loadSavedMeals() async {
    if (_savedMealsLoaded) return;
    if (!kIsWeb) {
      _savedMeals = await MealStorage.loadSavedMeals();
    }
    _savedMealsLoaded = true;
    notifyListeners();
  }

  Future<void> upsertSavedMeal(SavedMeal meal) async {
    if (!kIsWeb) {
      await MealStorage.upsertSavedMeal(meal);
    }
    final idx = _savedMeals.indexWhere((m) => m.id == meal.id);
    if (idx >= 0) {
      _savedMeals = [..._savedMeals]..[idx] = meal;
    } else {
      _savedMeals = [..._savedMeals, meal];
    }
    notifyListeners();
  }

  Future<void> deleteSavedMeal(String id) async {
    if (!kIsWeb) {
      await MealStorage.deleteSavedMeal(id);
    }
    _savedMeals = _savedMeals.where((m) => m.id != id).toList();
    notifyListeners();
  }

  /// Logs every item in [meal] as individual MealEntry records.
  Future<void> logSavedMeal(SavedMeal meal, MealType mealType) async {
    for (final item in meal.items) {
      await addEntry(
        food: item.foodItem,
        multiplier: item.quantityMultiplier,
        mealType: mealType,
      );
    }
  }

  // ── Weekly data ────────────────────────────────────────────────────────────

  Future<void> loadWeeklyData() async {
    if (_weeklyLoaded) return;
    if (kIsWeb) {
      _weeklyEntries = {};
      _weeklyLoaded = true;
      notifyListeners();
      return;
    }
    _weeklyEntries = await MealStorage.entriesForLastDays(7);
    _weeklyLoaded = true;
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmtDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
