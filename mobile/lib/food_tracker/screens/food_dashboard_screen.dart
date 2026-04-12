import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/food_tracker_provider.dart';
import '../widgets/meal_entry_card.dart';
import '../widgets/nutrient_progress_bar.dart';
import 'camera_scan_screen.dart';
import 'food_search_screen.dart';
import 'goals_screen.dart';
import 'meal_log_screen.dart';
import 'weekly_chart_screen.dart';

/// Primary dashboard for the food tracker.
/// Shows date navigation, daily nutrient progress bars, quick action buttons,
/// and a scrollable list of today's meals.
class FoodDashboardScreen extends StatefulWidget {
  const FoodDashboardScreen({super.key});

  @override
  State<FoodDashboardScreen> createState() => _FoodDashboardScreenState();
}

class _FoodDashboardScreenState extends State<FoodDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FoodTrackerProvider>().init();
    });
  }

  // ── Navigation helpers ─────────────────────────────────────────────────────

  Future<void> _pickDate(BuildContext context) async {
    final provider = context.read<FoodTrackerProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) await provider.selectDate(picked);
  }

  void _openSearch(BuildContext context, {String? prefill}) {
    context.read<FoodTrackerProvider>().clearSearch();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(prefilledQuery: prefill),
      ),
    );
  }

  /// Launches camera scan (mobile only), then opens search with the result.
  Future<void> _scanCamera(BuildContext context) async {
    final nav = Navigator.of(context);
    final provider = context.read<FoodTrackerProvider>();
    final result = await nav.push<String>(
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      provider.clearSearch();
      // ignore: use_build_context_synchronously
      _openSearch(context, prefill: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<FoodTrackerProvider>(
        builder: (_, provider, __) {
          final goals = provider.goals;
          final isToday = _isToday(provider.selectedDate);
          final dateLabel = isToday
              ? 'Today'
              : DateFormat('EEEE, MMM d').format(provider.selectedDate);

          return CustomScrollView(
            slivers: [
              // ── App bar ──────────────────────────────────────────────────
              SliverAppBar(
                title: const Text('Food Tracker'),
                floating: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.bar_chart),
                    tooltip: 'Weekly trends',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WeeklyChartScreen(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.flag_outlined),
                    tooltip: 'Edit goals',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GoalsScreen(),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Date navigation row ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => provider.selectDate(
                          provider.selectedDate
                              .subtract(const Duration(days: 1)),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _pickDate(context),
                          child: Text(
                            dateLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: isToday
                            ? null
                            : () => provider.selectDate(
                                  provider.selectedDate
                                      .add(const Duration(days: 1)),
                                ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Progress card ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Daily Progress',
                                style:
                                    Theme.of(context).textTheme.titleSmall),
                            Text(
                              '${provider.totalCalories.toStringAsFixed(0)} / ${goals.calories.toStringAsFixed(0)} kcal',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        NutrientProgressBar(
                          label: 'Calories',
                          consumed: provider.totalCalories,
                          goal: goals.calories,
                          unit: 'kcal',
                          progressColors: const [
                            Color(0xFFFFCAAF), // 25 % – bright peach
                            Color(0xFFFF9B6A), // 50 %
                            Color(0xFFFF6830), // 75 %
                            Color(0xFFFF4500), // 100 % – vivid coral-orange
                          ],
                        ),
                        NutrientProgressBar(
                          label: 'Protein',
                          consumed: provider.totalProtein,
                          goal: goals.protein,
                          progressColors: const [
                            Color(0xFFA3EEC0), // 25 % – bright mint
                            Color(0xFF4DD88A), // 50 %
                            Color(0xFF1AB85E), // 75 %
                            Color(0xFF0A9E4A), // 100 % – vivid green
                          ],
                        ),
                        NutrientProgressBar(
                          label: 'Carbs',
                          consumed: provider.totalCarbs,
                          goal: goals.carbs,
                          progressColors: const [
                            Color(0xFFA3EEC0), // 25 % – bright mint
                            Color(0xFF4DD88A), // 50 %
                            Color(0xFF1AB85E), // 75 %
                            Color(0xFF0A9E4A), // 100 % – vivid green
                          ],
                        ),
                        NutrientProgressBar(
                          label: 'Fat',
                          consumed: provider.totalFat,
                          goal: goals.fat,
                          progressColors: const [
                            Color(0xFFA3EEC0), // 25 % – bright mint
                            Color(0xFF4DD88A), // 50 %
                            Color(0xFF1AB85E), // 75 %
                            Color(0xFF0A9E4A), // 100 % – vivid green
                          ],
                        ),
                        NutrientProgressBar(
                          label: 'Iron',
                          consumed: provider.totalIron,
                          goal: goals.iron,
                          unit: 'mg',
                          progressColors: const [
                            Color(0xFFDDB3FF), // 25 % – bright lavender
                            Color(0xFFBB6BFF), // 50 %
                            Color(0xFF9933EE), // 75 %
                            Color(0xFF7B1FD8), // 100 % – vivid purple
                          ],
                          statusTextColors: const [
                            Colors.red,    // < 1/3
                            Colors.amber,  // 1/3 – 90 %
                            Colors.green,  // ≥ 90 %
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Action buttons ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.search,
                          label: 'Search Food',
                          onTap: () => _openSearch(context),
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.camera_alt,
                            label: 'Scan Food',
                            onTap: () => _scanCamera(context),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.list_alt,
                          label: 'Full Log',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MealLogScreen(
                                  date: provider.selectedDate),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Meals section header ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Meals',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),

              // ── Meal list or empty state ─────────────────────────────────
              if (provider.isLoading)
                const SliverToBoxAdapter(
                  child: Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )),
                )
              else if (provider.entries.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No meals logged yet.\nTap "Search Food" or "Scan Food" to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => MealEntryCard(entry: provider.entries[i]),
                    childCount: provider.entries.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

// ── Compact action card ────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
