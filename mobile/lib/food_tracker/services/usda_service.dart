import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/food_item.dart';
import 'meal_storage.dart';

/// USDA FoodData Central API wrapper.
/// Search results are cached in SQLite for 24 hours.
class UsdaService {
  // Replace with --dart-define=USDA_API_KEY=<your_key> at build time,
  // or set the env variable. Falls back to the project's existing key.
  static const _apiKey = String.fromEnvironment(
    'USDA_API_KEY',
    defaultValue: '9KaBngBH5d2bAT8kT3X57rl4ZyhOXPDcI8d1y6ag',
  );

  static const _baseUrl = 'https://api.nal.usda.gov/fdc/v1';

  // ── Search ─────────────────────────────────────────────────────────────────

  /// Search USDA for [query]. Returns up to [pageSize] results.
  /// Results are cached per-query for 24 hours (SQLite).
  static Future<List<FoodItem>> search(
    String query, {
    int pageSize = 25,
  }) async {
    if (query.trim().isEmpty) return [];

    // Check cache first (skip cache on web — sqflite not available)
    if (!kIsWeb) {
      final cached = await MealStorage.getCachedSearch(query);
      if (cached != null) {
        return _parseFoods(cached);
      }
    }

    final uri = Uri.parse('$_baseUrl/foods/search').replace(
      queryParameters: {
        'query': query,
        'api_key': _apiKey,
        'pageSize': pageSize.toString(),
        'dataType': 'Foundation,SR Legacy,Branded',
      },
    );

    final response =
        await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('USDA returned status ${response.statusCode}');
    }

    // Cache raw response
    if (!kIsWeb) {
      await MealStorage.cacheSearch(query, response.body);
    }

    return _parseFoods(response.body);
  }

  /// Fetch full nutrient details for a specific fdcId.
  static Future<FoodItem?> fetchById(String fdcId) async {
    try {
      final uri = Uri.parse('$_baseUrl/food/$fdcId').replace(
        queryParameters: {'api_key': _apiKey},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Detail endpoint returns 'foodNutrients' with a nested structure
      // Normalize to the same shape as search results so FoodItem.fromUsda works.
      final normalizedNutrients = (data['foodNutrients'] as List? ?? [])
          .map((n) => {
                'nutrientName': (n['nutrient']?['name'] ?? n['nutrientName'] ?? ''),
                'value': n['amount'] ?? n['value'] ?? 0,
              })
          .toList();

      return FoodItem.fromUsda({
        ...data,
        'foodNutrients': normalizedNutrients,
      });
    } catch (e) {
      debugPrint('USDA fetchById exception: $e');
      return null;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static List<FoodItem> _parseFoods(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final foods = data['foods'];
      if (foods is! List) return [];
      return foods
          .cast<Map<String, dynamic>>()
          .map(FoodItem.fromUsda)
          .toList();
    } catch (e) {
      debugPrint('USDA parse error: $e');
      return [];
    }
  }
}
