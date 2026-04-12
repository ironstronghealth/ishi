import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import 'nutrition_results_page.dart';

class FoodPage extends StatefulWidget {
  final CameraDescription camera;

  const FoodPage({super.key, required this.camera});

  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  final TextEditingController _foodController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _foodController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Tracking Camera')),
      body: Column(
        children: [
          // Manual food input (web/desktop)
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _foodController,
                      decoration: const InputDecoration(
                        labelText: 'Enter food name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    child: const Text('Search'),
                    onPressed: () async {
                      final food = _foodController.text.trim();
                      if (food.isEmpty) {
                        _showMessage('Please enter a food name.');
                        return;
                      }

                      final nutrition =
                          await FoodAnalyzer.fetchNutrition(food);

                      if (!mounted) return;

                      if (nutrition == null) {
                        _showMessage(
                          'No nutrition data found for "$food". Try a different name.',
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NutritionResultPage(
                            imagePath: null,
                            foodName: food,
                            nutrition: nutrition,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          // Camera preview (mobile)
          Expanded(
            child: FutureBuilder(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return CameraPreview(_controller);
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.camera_alt),
        onPressed: () async {
          try {
            await _initializeControllerFuture;
            final image = await _controller.takePicture();

            if (!mounted) return;

            final food = await FoodAnalyzer.detectFood(image.path);

            if (food == null || food.length < 3) {
              _showMessage(
                'Could not confidently identify the food. Try manual search.',
              );
              return;
            }

            final nutrition =
                await FoodAnalyzer.fetchNutrition(food);

            if (nutrition == null) {
              _showMessage('No nutrition data found for "$food".');
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NutritionResultPage(
                  imagePath: image.path,
                  foodName: food,
                  nutrition: nutrition,
                ),
              ),
            );
          } catch (e) {
            _showMessage('Camera error. Please try again.');
          }
        },
      ),
    );
  }
}

class FoodAnalyzer {
  static final ImageLabeler _labeler =
      ImageLabeler(options: ImageLabelerOptions());

  static Future<String?> detectFood(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final labels = await _labeler.processImage(inputImage);

      if (labels.isEmpty) return null;

      labels.sort((a, b) => b.confidence.compareTo(a.confidence));
      return labels.first.label.toLowerCase();
    } catch (e) {
      debugPrint('MLKit error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchNutrition(String food) async {
    try {
      const apiKey = '9KaBngBH5d2bAT8kT3X57rl4ZyhOXPDcI8d1y6ag';

      final uri = Uri.parse(
        'https://api.nal.usda.gov/fdc/v1/foods/search'
        '?query=$food&api_key=$apiKey',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);

      if (data == null ||
          data['foods'] == null ||
          data['foods'] is! List ||
          data['foods'].isEmpty) {
        return null;
      }

      return data['foods'][0];
    } catch (e) {
      debugPrint('USDA fetch error: $e');
      return null;
    }
  }
}