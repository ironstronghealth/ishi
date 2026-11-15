import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/food_item.dart';
import '../models/library_food.dart';
import '../models/meal_entry.dart';
import '../models/saved_meal.dart';

/// SQLite-backed storage for MealEntry objects.
/// Also caches USDA search results as raw JSON strings.
class MealStorage {
  static Database? _db;

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'food_tracker.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE meal_entries (
            id TEXT PRIMARY KEY,
            foodItem TEXT NOT NULL,
            quantityMultiplier REAL NOT NULL,
            timestamp TEXT NOT NULL,
            mealType TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE usda_cache (
            query TEXT PRIMARY KEY,
            results TEXT NOT NULL,
            cachedAt TEXT NOT NULL
          )
        ''');
        await _createSavedMealsTable(db);
        await _createFoodLibraryTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSavedMealsTable(db);
        }
        if (oldVersion < 3) {
          await _createFoodLibraryTable(db);
          await _seedFoodLibraryFromHistory(db);
        }
      },
    );
  }

  // ── MealEntry CRUD ─────────────────────────────────────────────────────────

  /// Insert or replace a meal entry.
  static Future<void> saveMeal(MealEntry entry) async {
    final db = await database;
    await db.insert(
      'meal_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a meal entry by id.
  static Future<void> deleteMeal(String id) async {
    final db = await database;
    await db.delete('meal_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns all entries for a given calendar date (local time).
  static Future<List<MealEntry>> entriesForDate(DateTime date) async {
    final db = await database;
    // Compare ISO date prefix (YYYY-MM-DD) — stored as ISO8601 string
    final prefix = _dateKey(date);
    final rows = await db.query(
      'meal_entries',
      where: "timestamp LIKE ?",
      whereArgs: ['$prefix%'],
      orderBy: 'timestamp ASC',
    );
    return rows.map(MealEntry.fromMap).toList();
  }

  /// Returns all entries between [start] and [end] dates inclusive.
  static Future<List<MealEntry>> entriesForDateRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final startStr = _dateKey(start);
    final endStr = _dateKey(end.add(const Duration(days: 1)));
    final rows = await db.query(
      'meal_entries',
      where: "timestamp >= ? AND timestamp < ?",
      whereArgs: [startStr, endStr],
      orderBy: 'timestamp ASC',
    );
    return rows.map(MealEntry.fromMap).toList();
  }

  /// Returns entries for each of the last [days] days (oldest first).
  /// Returns a map keyed by date string (YYYY-MM-DD).
  static Future<Map<String, List<MealEntry>>> entriesForLastDays(
      int days) async {
    final db = await database;
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final rows = await db.query(
      'meal_entries',
      where: "timestamp >= ?",
      whereArgs: [cutoff.toIso8601String()],
      orderBy: 'timestamp ASC',
    );

    final result = <String, List<MealEntry>>{};
    for (final row in rows) {
      final entry = MealEntry.fromMap(row);
      final key = _dateKey(entry.timestamp);
      result.putIfAbsent(key, () => []).add(entry);
    }
    return result;
  }

  // ── USDA cache ─────────────────────────────────────────────────────────────

  static const _cacheTtlHours = 24;

  /// Returns cached JSON string for [query], or null if missing / expired.
  static Future<String?> getCachedSearch(String query) async {
    final db = await database;
    final rows = await db.query(
      'usda_cache',
      where: 'query = ?',
      whereArgs: [query.toLowerCase()],
    );
    if (rows.isEmpty) return null;

    final cachedAt = DateTime.parse(rows.first['cachedAt'] as String);
    if (DateTime.now().difference(cachedAt).inHours > _cacheTtlHours) {
      return null; // expired
    }
    return rows.first['results'] as String;
  }

  /// Store a search result string for [query].
  static Future<void> cacheSearch(String query, String resultsJson) async {
    final db = await database;
    await db.insert(
      'usda_cache',
      {
        'query': query.toLowerCase(),
        'results': resultsJson,
        'cachedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Saved meals ────────────────────────────────────────────────────────────

  static Future<void> _createSavedMealsTable(Database db) => db.execute('''
        CREATE TABLE saved_meals (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          items TEXT NOT NULL
        )
      ''');

  static Future<List<SavedMeal>> loadSavedMeals() async {
    final db = await database;
    final rows = await db.query('saved_meals', orderBy: 'name ASC');
    return rows.map(SavedMeal.fromMap).toList();
  }

  static Future<void> upsertSavedMeal(SavedMeal meal) async {
    final db = await database;
    await db.insert(
      'saved_meals',
      meal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteSavedMeal(String id) async {
    final db = await database;
    await db.delete('saved_meals', where: 'id = ?', whereArgs: [id]);
  }

  // ── Food library (recents, favourites, custom foods, barcodes) ─────────────

  static Future<void> _createFoodLibraryTable(Database db) async {
    await db.execute('''
      CREATE TABLE food_library (
        id TEXT PRIMARY KEY,
        foodItem TEXT NOT NULL,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        isCustom INTEGER NOT NULL DEFAULT 0,
        barcode TEXT,
        useCount INTEGER NOT NULL DEFAULT 0,
        lastUsedAt TEXT
      )
    ''');
  }

  /// Existing users already have a meal history; use it so "Recent" and
  /// "Frequent" are populated straight after the upgrade.
  static Future<void> _seedFoodLibraryFromHistory(Database db) async {
    final rows = await db.query('meal_entries', orderBy: 'timestamp ASC');
    final byId = <String, LibraryFood>{};
    for (final row in rows) {
      try {
        final entry = MealEntry.fromMap(row);
        final prev = byId[entry.foodItem.id];
        byId[entry.foodItem.id] = LibraryFood(
          food: entry.foodItem,
          useCount: (prev?.useCount ?? 0) + 1,
          lastUsedAt: entry.timestamp,
        );
      } catch (_) {
        // Skip unreadable rows rather than failing the migration.
      }
    }
    final batch = db.batch();
    for (final f in byId.values) {
      batch.insert('food_library', _libraryRow(f),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Map<String, dynamic> _libraryRow(LibraryFood f) => {
        'id': f.food.id,
        'foodItem': jsonEncode(f.food.toMap()),
        'isFavorite': f.isFavorite ? 1 : 0,
        'isCustom': f.isCustom ? 1 : 0,
        'barcode': f.barcode,
        'useCount': f.useCount,
        'lastUsedAt': f.lastUsedAt?.toIso8601String(),
      };

  static Future<List<LibraryFood>> loadFoodLibrary() async {
    final db = await database;
    final rows = await db.query('food_library');
    final out = <LibraryFood>[];
    for (final r in rows) {
      try {
        final last = r['lastUsedAt'] as String?;
        out.add(LibraryFood(
          food: FoodItem.fromMap(
            jsonDecode(r['foodItem'] as String) as Map<String, dynamic>,
          ),
          isFavorite: r['isFavorite'] == 1,
          isCustom: r['isCustom'] == 1,
          barcode: r['barcode'] as String?,
          useCount: (r['useCount'] as int?) ?? 0,
          lastUsedAt: last == null ? null : DateTime.parse(last),
        ));
      } catch (_) {
        // Ignore a corrupt row instead of losing the whole library.
      }
    }
    return out;
  }

  static Future<void> upsertLibraryFood(LibraryFood f) async {
    final db = await database;
    await db.insert('food_library', _libraryRow(f),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteLibraryFood(String id) async {
    final db = await database;
    await db.delete('food_library', where: 'id = ?', whereArgs: [id]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
