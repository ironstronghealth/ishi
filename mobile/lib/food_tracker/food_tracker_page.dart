import 'package:flutter/material.dart';

import 'screens/food_dashboard_screen.dart';

/// Food tracker tab. The [FoodTrackerProvider] is owned by the root
/// [_ISHIAppState] so state persists across tab switches.
class FoodTrackerPage extends StatelessWidget {
  const FoodTrackerPage({super.key});

  @override
  Widget build(BuildContext context) => const FoodDashboardScreen();
}
