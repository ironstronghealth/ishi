import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // <-- import camera
import 'package:provider/provider.dart';
import 'pages/home_page.dart';
import 'pages/camera_page.dart'; // ISHI-AI Check
import 'pages/profile_page.dart';
import 'widgets/floating_nav.dart';
import 'pages/about_page.dart';
import 'food_tracker/food_tracker_page.dart'; // new full food tracker
import 'food_tracker/providers/food_tracker_provider.dart';
// Ensures Isar native libraries are bundled in release builds.
// import 'package:isar_flutter_libs/isar_flutter_libs.dart' as _;

// Global variable to store cameras
late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras(); // initialize cameras
  runApp(const ISHIApp());
}

class ISHIApp extends StatefulWidget {
  const ISHIApp({super.key});
  @override
  State<ISHIApp> createState() => _ISHIAppState();
}

class _ISHIAppState extends State<ISHIApp> {
  int _index = 0;
  final _foodProvider = FoodTrackerProvider();

  @override
  void dispose() {
    _foodProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _foodProvider,
      child: MaterialApp(
      title: 'ISHI App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2B5CFF),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2B5CFF),
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            children: [
              HomePage(),
              CameraPage(),          // ISHI-AI Check
              _EventsPage(),
              ProfilePage(),         // ← real Profile page (Google OAuth + local storage)
              const FoodTrackerPage(), // ← full food tracker (USDA + log + charts)
              AboutPage(),
              _DonatePage(),
            ],
          ),
        ),
        bottomNavigationBar: FloatingNavBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      ),
    ));
  }
}

// Lightweight placeholders (you can expand later)
class _EventsPage extends StatelessWidget {
  const _EventsPage();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Events coming soon'));
}

class _DonatePage extends StatelessWidget {
  const _DonatePage();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Donate link / QR here'));
}