import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../pages/food_page.dart'; // reuse FoodAnalyzer (ML Kit + USDA)

/// Mobile-only screen: lets user pick a photo, runs ML Kit food detection,
/// and returns the detected food label string to the caller via Navigator.pop.
///
/// Usage:
///   final label = await Navigator.push<String>(context,
///     MaterialPageRoute(builder: (_) => const CameraScanScreen()));
///   if (label != null) openSearch(label);
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  bool _scanning = false;
  final _picker = ImagePicker();

  Future<void> _scan(ImageSource source) async {
    setState(() => _scanning = true);
    try {
      final xFile = await _picker.pickImage(source: source, imageQuality: 85);
      if (xFile == null) {
        setState(() => _scanning = false);
        return;
      }

      final label = await FoodAnalyzer.detectFood(xFile.path);

      if (!mounted) return;

      if (label == null || label.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not identify food. Try searching manually.'),
          ),
        );
        Navigator.pop(context); // return null — let user search
      } else {
        Navigator.pop(context, label); // return detected label
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Food')),
      body: Center(
        child: _scanning
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Identifying food…'),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Take a photo or choose from your gallery to identify a food.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Take Photo'),
                        onPressed: () => _scan(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Choose from Gallery'),
                        onPressed: () => _scan(ImageSource.gallery),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel — search manually instead'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
