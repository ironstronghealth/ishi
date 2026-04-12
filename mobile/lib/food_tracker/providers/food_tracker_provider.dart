import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../models/nutrition_goals.dart';
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
