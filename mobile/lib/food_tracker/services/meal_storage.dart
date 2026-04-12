import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/meal_entry.dart';

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
      version: 1,
      onCreate: (db, _) async {
        // Meal entries table
        await db.execute('''
          CREATE TABLE meal_entries (
            id TEXT PRIMARY KEY,
            foodItem TEXT NOT NULL,
            quantityMultiplier REAL NOT NULL,
            timestamp TEXT NOT NULL,
            mealType TEXT NOT NULL
          )
        ''');

        // USDA search result cache
        await db.execute('''
          CREATE TABLE usda_cache (
            query TEXT PRIMARY KEY,
            results TEXT NOT NULL,
            cachedAt TEXT NOT NULL
          )
        ''');
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
