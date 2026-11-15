import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/meal_entry.dart';

/// Result returned by [VisionService.analyzeFood].
class FoodScanResult {
  final String searchQuery; // USDA-optimised query e.g. "grilled chicken breast"
  final double estimatedGrams; // AI portion estimate in grams
  final MealType suggestedMealType;
  final String description; // Human-readable label e.g. "Grilled chicken (~150 g)"
  final double confidence; // 0.0–1.0

  const FoodScanResult({
    required this.searchQuery,
    required this.estimatedGrams,
    required this.suggestedMealType,
    required this.description,
    required this.confidence,
  });
}

/// Calls the Gemini 1.5 Flash vision API to identify a food item in an image.
///
/// Set the API key at build / run time:
///   flutter run --dart-define=GEMINI_API_KEY=AIza...
///
/// Free tier: 15 requests/min, 1 500 requests/day (Google AI Studio).
class VisionService {
  static const _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const _model = 'gemini-1.5-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static const _prompt = '''
Analyze this food image and return ONLY a JSON object — no markdown, no explanation.

Use this exact structure:
{
  "searchQuery": "<food name optimised for USDA database, e.g. 'grilled chicken breast', 'white rice cooked', 'apple raw'>",
  "estimatedGrams": <integer — estimated weight in grams of the portion visible>,
  "mealType": "<breakfast|lunch|dinner|snack>",
  "description": "<short label e.g. 'Grilled chicken breast (~150 g)'>",
  "confidence": <0.0–1.0>
}

If no food is clearly visible return:
{"searchQuery":"","estimatedGrams":100,"mealType":"snack","description":"Unknown","confidence":0.0}
''';

  /// Returns null when:
  ///  - API key not configured
  ///  - Gemini cannot identify food (confidence < 0.4)
  ///  - Any network / parse error
  ///
  /// Caller should fall back to ML Kit + manual search in these cases.
  static Future<FoodScanResult?> analyzeFood(String imagePath) async {
    if (_apiKey.isEmpty) {
      debugPrint('VisionService: GEMINI_API_KEY not set — skipping');
      return null;
    }

    try {
      final bytes = await File(imagePath).readAsBytes();
      final b64 = base64Encode(bytes);

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
              },
              {'text': _prompt},
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 256,
        },
      });

      final uri = Uri.parse('$_endpoint?key=$_apiKey');
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint('VisionService: HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (data['candidates'] as List?)
          ?.firstOrNull?['content']?['parts']
              ?.firstOrNull?['text'] as String?;

      if (text == null || text.isEmpty) return null;

      // Strip any accidental markdown fences
      final cleaned =
          text.replaceAll('```json', '').replaceAll('```', '').trim();

      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
      if (confidence < 0.4) return null;

      final mealTypeStr = (json['mealType'] as String? ?? '').toLowerCase();
      final mealType = MealType.values.firstWhere(
        (m) => m.name == mealTypeStr,
        orElse: _mealTypeFromTime,
      );

      return FoodScanResult(
        searchQuery: (json['searchQuery'] as String? ?? '').trim(),
        estimatedGrams:
            (json['estimatedGrams'] as num?)?.toDouble() ?? 100.0,
        suggestedMealType: mealType,
        description: json['description'] as String? ?? 'Food item',
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('VisionService error: $e');
      return null;
    }
  }

  static MealType _mealTypeFromTime() {
    final h = DateTime.now().hour;
    if (h < 10) return MealType.breakfast;
    if (h < 14) return MealType.lunch;
    if (h < 19) return MealType.dinner;
    return MealType.snack;
  }
}
