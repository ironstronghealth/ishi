// lib/pages/camera_page.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Read the backend base URL from a build-time define:
/// flutter run/build ... --dart-define=API_BASE_URL=https://ishi-api.onrender.com
const String _apiBase =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');

// Light network hardening
const _kTimeoutSec = 15;   // connect/read timeout per attempt
const _kMaxAttempts = 3;   // upload attempts (with tiny backoff)

Uri _joinPath(Uri base, String path) {
  if (path.startsWith('/')) {
    return base.replace(path: path, query: '');
  }
  final p = base.path.endsWith('/') ? '${base.path}$path' : '${base.path}/$path';
  return base.replace(path: p, query: '');
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _HomeDisclaimerBanner extends StatelessWidget {
  const _HomeDisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informational only — not a diagnosis or a medical device. '
                    'Consult a qualified clinician for medical concerns.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.ironstronginitiative.com/privacy'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraPageState extends State<CameraPage> {
  final _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _result;
  String? _detail;
  bool _loading = false;
  List<Map<String, String>> _history = [];

  Uri? get _apiBaseUri {
    if (_apiBase.isEmpty) return null;
    final u = Uri.tryParse(_apiBase);
    return (u == null || !u.hasScheme) ? null : u;
  }

  Uri? _predictUri() => _apiBaseUri == null ? null : _joinPath(_apiBaseUri!, '/predict');
  Uri? _healthUri() => _apiBaseUri == null ? null : _joinPath(_apiBaseUri!, '/health');

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _result = null;
      _detail = null;
    });
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _result = null;
      _detail = null;
    });
  }

  Future<void> _submitImage() async {
    if (_imageBytes == null) return;
    final uri = _predictUri();
    if (uri == null) {
      setState(() {
        _result = 'API not configured';
        _detail = 'Pass --dart-define=API_BASE_URL=https://your-api';
      });
      return;
    }

    setState(() => _loading = true);

    try {
      int attempts = 0;
      Object? lastErr;
      while (attempts < _kMaxAttempts) {
        attempts++;
        try {
          final req = http.MultipartRequest('POST', uri)
            ..files.add(http.MultipartFile.fromBytes(
              'image',
              _imageBytes!,
              filename: 'upload.jpg',
              contentType: MediaType('image', 'jpeg'),
            ));

          final streamed = await req.send().timeout(const Duration(seconds: _kTimeoutSec));
          final res = await http.Response.fromStream(streamed)
              .timeout(const Duration(seconds: _kTimeoutSec));

          if (res.statusCode == 200) {
            final m = jsonDecode(res.body) as Map<String, dynamic>;
            final isAnemic = m['anemic'] == true;
            final score = (m['score'] is num) ? (m['score'] as num).toDouble() : 0.0;
            final pct = (score * 100).toStringAsFixed(1);
            final cropper = (m['cropper'] ?? 'n/a').toString();

            final resultText = isAnemic ? 'Anemic' : 'Not Anemic';
            final detailText = 'Score: $pct% • Cropper: $cropper';

            final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
            final entry = {'timestamp': ts, 'result': resultText};

            final prefs = await SharedPreferences.getInstance();
            setState(() {
              _result = resultText;
              _detail = detailText;
              _history.insert(0, entry);
            });
            await prefs.setString('ishi_test_history', jsonEncode(_history));
            return;
          } else {
            lastErr = 'HTTP ${res.statusCode}: ${res.body}';
          }
        } catch (e) {
          lastErr = e;
        }
        await Future.delayed(Duration(milliseconds: 250 * attempts * attempts));
      }

      setState(() {
        _result = 'Network error';
        _detail = 'Upload failed after $_kMaxAttempts attempts: $lastErr';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testHealth() async {
    final u = _healthUri();
    if (u == null) {
      setState(() {
        _result = 'API not configured';
        _detail = 'Pass --dart-define=API_BASE_URL=https://your-api';
      });
      return;
    }
    try {
      final r = await http.get(u).timeout(const Duration(seconds: _kTimeoutSec));
      setState(() {
        _result = 'Health ${r.statusCode}';
        _detail = r.body;
      });
    } catch (e) {
      setState(() {
        _result = 'Health error';
        _detail = e.toString();
      });
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('ishi_test_history');
    if (saved != null) {
      final decoded = jsonDecode(saved);
      final list = (decoded as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
      setState(() {
        _history = list;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final api = _apiBaseUri;
    final apiText = api == null
        ? 'API: (not set)'
        : 'API: ${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}${api.path}';

    return Scaffold(
      appBar: AppBar(title: const Text('Anemia Checker')),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(onPressed: _testHealth, child: const Text('Test API')),
                    const SizedBox(width: 12),
                    Flexible(
                      child: SelectableText(
                        apiText,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _HomeDisclaimerBanner(),
                const SizedBox(height: 16),
                const Text(
                  'About Anemia',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Anemia is a condition where you lack enough healthy red blood cells to carry adequate oxygen to your body\'s tissues. Detecting it early can help prevent fatigue, weakness, and more serious complications.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_imageBytes != null) ...[
                  const Text('Selected Image:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_imageBytes!, height: 200),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_loading)
                  const CircularProgressIndicator()
                else if (_result != null)
                  Card(
                    color: _result == 'Anemic' ? Colors.red[100] : Colors.green[100],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            _result!,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _result == 'Anemic' ? Colors.red[800] : Colors.green[800],
                            ),
                          ),
                          if (_detail != null) ...[
                            const SizedBox(height: 6),
                            Text(_detail!, style: const TextStyle(fontSize: 14)),
                          ],
                          const SizedBox(height: 10),
                          const Text(
                            'Informational only — not a diagnosis or a medical device.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _pickFromGallery,
                      child: const Text('Upload Eyelid Image'),
                    ),
                    ElevatedButton(
                      onPressed: _takePhoto,
                      child: Text(kIsWeb ? 'Capture (Browser Prompt)' : 'Capture from Camera'),
                    ),
                    ElevatedButton(
                      onPressed: _imageBytes == null || _loading ? null : _submitImage,
                      child: const Text('Check for Anemia'),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                if (_history.isNotEmpty) ...[
                  const Divider(),
                  const Text('Test History',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  ..._history
                      .map((entry) => ListTile(
                            leading: Icon(
                              entry['result'] == 'Anemic' ? Icons.warning : Icons.check_circle,
                              color: entry['result'] == 'Anemic' ? Colors.red : Colors.green,
                            ),
                            title: Text(entry['result']!),
                            subtitle: Text(entry['timestamp']!),
                          ))
                      .toList(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
