import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nutrition_goals.dart';
import '../providers/food_tracker_provider.dart';

/// Screen for editing daily nutrition goals.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _calCtrl;
  late TextEditingController _proCtrl;
  late TextEditingController _carbCtrl;
  late TextEditingController _fatCtrl;
  late TextEditingController _ironCtrl;

  @override
  void initState() {
    super.initState();
    final g = context.read<FoodTrackerProvider>().goals;
    _calCtrl = TextEditingController(text: g.calories.toStringAsFixed(0));
    _proCtrl = TextEditingController(text: g.protein.toStringAsFixed(0));
    _carbCtrl = TextEditingController(text: g.carbs.toStringAsFixed(0));
    _fatCtrl = TextEditingController(text: g.fat.toStringAsFixed(0));
    _ironCtrl = TextEditingController(text: g.iron.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _proCtrl.dispose();
    _carbCtrl.dispose();
    _fatCtrl.dispose();
    _ironCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim()) ?? fallback;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final goals = NutritionGoals(
      calories: _parse(_calCtrl, 2000),
      protein: _parse(_proCtrl, 50),
      carbs: _parse(_carbCtrl, 275),
      fat: _parse(_fatCtrl, 78),
      iron: _parse(_ironCtrl, 18),
    );
    await context.read<FoodTrackerProvider>().updateGoals(goals);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Goals saved.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Goals')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Set your daily nutrition targets. Progress bars on the dashboard use these values.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _GoalField(
              controller: _calCtrl,
              label: 'Calories (kcal)',
              icon: Icons.local_fire_department,
            ),
            _GoalField(
              controller: _proCtrl,
              label: 'Protein (g)',
              icon: Icons.fitness_center,
            ),
            _GoalField(
              controller: _carbCtrl,
              label: 'Carbohydrates (g)',
              icon: Icons.grain,
            ),
            _GoalField(
              controller: _fatCtrl,
              label: 'Fat (g)',
              icon: Icons.water_drop,
            ),
            _GoalField(
              controller: _ironCtrl,
              label: 'Iron (mg)',
              icon: Icons.bloodtype,
            ),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: _save, child: const Text('Save Goals')),
          ],
        ),
      ),
    );
  }
}

class _GoalField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _GoalField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
        validator: (v) {
          final n = double.tryParse(v?.trim() ?? '');
          if (n == null || n <= 0) return 'Enter a positive number';
          return null;
        },
      ),
    );
  }
}
