import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/food_item.dart';
import '../providers/food_tracker_provider.dart';
import '../services/barcode_service.dart';
import 'custom_food_screen.dart';

/// Live camera barcode scanner for packaged foods.
///
/// Pops with the matching [FoodItem] once a barcode is recognised and found
/// in a product database, or with null if the user backs out.
///
/// Usage:
///   final food = await Navigator.push<FoodItem>(context,
///     MaterialPageRoute(builder: (_) => const BarcodeScanScreen()));
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );

  bool _lookingUp = false;
  String? _message; // shown after a failed lookup
  String? _lastCode;
  String? _failedCode; // last valid code whose lookup failed

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_lookingUp) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && BarcodeService.isValidBarcode(code)) {
        _lookup(code);
        return;
      }
    }
  }

  Future<void> _lookup(String code) async {
    if (_lookingUp) return;
    final provider = context.read<FoodTrackerProvider>();
    setState(() {
      _lookingUp = true;
      _message = null;
      _failedCode = null;
      _lastCode = code;
    });
    HapticFeedback.mediumImpact();
    // Pause the camera while we hit the network so we don't re-detect.
    // The camera may not be running (permission denied + manual entry), so
    // stop/start failures are not fatal.
    try {
      await _controller.stop();
    } catch (_) {}

    // Foods the user created for this barcode, or scanned before, resolve
    // instantly and offline.
    FoodItem? food = provider.foodForBarcode(code);
    String? failure;
    if (food == null) {
      try {
        food = await BarcodeService.lookup(code);
        if (food == null) {
          failure = 'No product found for barcode $code.';
        } else {
          await provider.rememberBarcode(food, code);
        }
      } catch (_) {
        failure = 'Could not look up the product. Check your connection.';
      }
    }

    if (!mounted) return;

    if (food != null) {
      Navigator.pop(context, food);
      return;
    }

    setState(() {
      _lookingUp = false;
      _message = failure;
      _failedCode = code;
    });
    try {
      await _controller.start();
    } catch (_) {}
  }

  /// Lets the user type in the label for a product no database knows; it is
  /// saved against the barcode so the next scan finds it.
  Future<void> _addProduct(String code) async {
    try {
      await _controller.stop();
    } catch (_) {}
    if (!mounted) return;

    final food = await Navigator.push<FoodItem>(
      context,
      MaterialPageRoute(builder: (_) => CustomFoodScreen(barcode: code)),
    );
    if (!mounted) return;

    if (food != null) {
      Navigator.pop(context, food);
      return;
    }
    try {
      await _controller.start();
    } catch (_) {}
  }

  Future<void> _enterManually() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 14,
          decoration: const InputDecoration(
            hintText: 'Digits printed under the barcode',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Look up'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;

    final trimmed = code.trim();
    if (!BarcodeService.isValidBarcode(trimmed)) {
      setState(() {
        _message = 'Barcodes are 8, 12, 13 or 14 digits long.';
        _failedCode = null;
      });
      return;
    }
    await _lookup(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Enter barcode manually',
            onPressed: _lookingUp ? null : _enterManually,
          ),
          IconButton(
            icon: const Icon(Icons.flashlight_on),
            tooltip: 'Toggle flashlight',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(
              error: error,
              onEnterManually: _enterManually,
            ),
          ),

          // Aiming guide
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Status / hint
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _lookingUp
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Looking up ${_lastCode ?? 'product'}…',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _message ??
                              'Point the camera at a food package barcode.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (_message != null && _failedCode != null) ...[
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () => _addProduct(_failedCode!),
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Enter this product yourself'),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'or scan another barcode',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onEnterManually;

  const _CameraError({required this.error, required this.onEnterManually});

  @override
  Widget build(BuildContext context) {
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 48, color: Colors.white70),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'Camera access is needed to scan barcodes. '
                        'Enable it in your device settings.'
                    : error.errorCode == MobileScannerErrorCode.unsupported
                        ? 'No camera was found. Simulators and emulators '
                            'do not have one, so type the barcode digits '
                            'instead.'
                        : 'The camera could not be started.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onEnterManually,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter barcode manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
