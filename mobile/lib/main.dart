import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/camera_page.dart'; // pushed after disclaimer
import 'pages/profile_page.dart';
import 'pages/about_page.dart';

import 'widgets/floating_nav.dart';
import 'widgets/disclaimer_gate.dart';

void main() => runApp(const ISHIApp());

class ISHIApp extends StatefulWidget {
  const ISHIApp({super.key});
  @override
  State<ISHIApp> createState() => _ISHIAppState();
}

class _ISHIAppState extends State<ISHIApp> {
  // Navigator key so dialogs/pushes always have a valid Navigator
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  int _index = 0;

  // Intercept AI Check (index 1): show disclaimer, then push CameraPage
  Future<void> _handleNavTap(int i) async {
    const aiCheckIndex = 1; // "ISHI-AI Check"

    if (i == aiCheckIndex) {
      // Show disclaimer using a Navigator-aware context
      final ctx = _navKey.currentContext ?? context;
      final ok = await DisclaimerGate.ensureAccepted(ctx, alwaysShow: true);
      if (!ok) return;

      // Push AFTER the dialog fully closes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = _navKey.currentState;
        if (nav == null) return;
        nav.push(MaterialPageRoute(builder: (_) => const CameraPage()));
      });

      return; // don't fall through and switch tabs
    }

    // Normal tab switch for other items
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ISHI App',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2B5CFF)),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2B5CFF),
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            // Keep indices aligned with FloatingNavBar items (0..5)
            children: const [
              HomePage(),             // 0
              _AiCheckPlaceholder(),  // 1 (AI Check handled via push, not a tab)
              _EventsPage(),          // 2
              ProfilePage(),          // 3
              AboutPage(),            // 4
              _DonatePage(),          // 5
            ],
          ),
        ),
        bottomNavigationBar: FloatingNavBar(
          currentIndex: _index,
          onTap: _handleNavTap,
        ),
      ),
    );
  }
}

// ---------- Placeholders to keep indices aligned ----------
class _AiCheckPlaceholder extends StatelessWidget {
  const _AiCheckPlaceholder();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _EventsPage extends StatelessWidget {
  const _EventsPage();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Events coming soon'));
}

class _DonatePage extends StatelessWidget {
  const _DonatePage();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Donate link / QR here'));
}
