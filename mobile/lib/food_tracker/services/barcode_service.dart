import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/food_item.dart';
import 'usda_service.dart';

/// Looks up packaged food products by barcode (UPC / EAN).
///
/// Primary source is Open Food Facts (free, no API key, best barcode
/// coverage). Falls back to USDA Branded Foods, which indexes by GTIN/UPC.
class BarcodeService {
  static const _offBaseUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _offFields =
      'product_name,generic_name,brands,nutriments,serving_quantity';

  /// Returns the product for [barcode], or null when no source knows it.
  /// Throws on network failure so callers can distinguish "not found" from
  /// "couldn't reach the server".
  static Future<FoodItem?> lookup(String barcode) async {
    final code = barcode.trim();
    if (!isValidBarcode(code)) return null;

    Object? firstError;

    try {
      final food = await _lookupOpenFoodFacts(code);
      if (food != null) return food;
    } catch (e) {
      debugPrint('Open Food Facts lookup failed: $e');
      firstError = e;
    }

    try {
      final food = await UsdaService.fetchByBarcode(code);
      if (food != null) return food;
    } catch (e) {
      debugPrint('USDA barcode lookup failed: $e');
      firstError ??= e;
    }

    // Only surface an error if no source gave a definitive "not found".
    if (firstError != null) throw firstError;
    return null;
  }

  /// Retail food barcodes are 8 (EAN-8/UPC-E), 12 (UPC-A), 13 (EAN-13) or
  /// 14 (GTIN-14) digits.
  static bool isValidBarcode(String code) =>
      RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(code);

  // ── Open Food Facts ────────────────────────────────────────────────────────

  static Future<FoodItem?> _lookupOpenFoodFacts(String code) async {
    final uri = Uri.parse('$_offBaseUrl/$code.json')
        .replace(queryParameters: {'fields': _offFields});

    final response = await http.get(
      uri,
      headers: {'User-Agent': 'FoodTrackerApp/1.0 (Flutter)'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Open Food Facts returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final product = data['product'];
    if (data['status'] != 1 || product is! Map<String, dynamic>) return null;

    return parseOpenFoodFacts(code, product);
  }

  /// Converts an Open Food Facts product into a [FoodItem]. Returns null when
  /// the product has no usable name or nutrition data.
  @visibleForTesting
  static FoodItem? parseOpenFoodFacts(
    String code,
    Map<String, dynamic> product,
  ) {
    final name = _firstNonEmpty([
      product['product_name'],
      product['generic_name'],
    ]);
    final nutriments = product['nutriments'];
    if (name == null || nutriments is! Map) return null;

    double per100(String key) => _toDouble(nutriments['${key}_100g']);

    var calories = per100('energy-kcal');
    if (calories == 0) calories = per100('energy') / 4.184; // kJ → kcal
    final protein = per100('proteins');
    final carbs = per100('carbohydrates');
    final fat = per100('fat');
    // Open Food Facts stores minerals in grams; the app tracks iron in mg.
    final iron = per100('iron') * 1000;

    // A product page with no nutrition facts would log as all zeros.
    if (calories == 0 && protein == 0 && carbs == 0 && fat == 0) return null;

    // Prefer the label's serving size so "1×" means one serving of the
    // product; otherwise fall back to the per-100 g basis used by USDA items.
    final servingGrams = _toDouble(product['serving_quantity']);
    final hasServing = servingGrams > 0 && servingGrams <= 2000;
    final scale = hasServing ? servingGrams / 100.0 : 1.0;

    final brand = _firstNonEmpty([product['brands']])?.split(',').first.trim();

    return FoodItem(
      id: 'off_$code',
      name: name,
      calories: calories * scale,
      protein: protein * scale,
      carbs: carbs * scale,
      fat: fat * scale,
      iron: iron * scale,
      servingSize: hasServing ? servingGrams : 100.0,
      brand: (brand == null || brand.isEmpty) ? null : brand,
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
