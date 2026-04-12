import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/food_tracker_provider.dart';
import '../services/meal_storage.dart';

/// Iron progress line chart — one week at a time (Sun → Sat),
/// with left/right arrows to navigate past weeks.
class WeeklyChartScreen extends StatefulWidget {
  const WeeklyChartScreen({super.key});

  @override
  State<WeeklyChartScreen> createState() => _WeeklyChartScreenState();
}

class _WeeklyChartScreenState extends State<WeeklyChartScreen> {
  // 0 = current week, -1 = last week, -2 = two weeks ago …
  int _weekOffset = 0;
  Map<String, double> _ironByDay = {};
  bool _loading = true;

  // ── Week math ───────────────────────────────────────────────────────────────

  DateTime get _sundayOfThisWeek {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Dart weekday: 1=Mon … 7=Sun; shift so Sunday = 0
    final offset = today.weekday == DateTime.sunday ? 0 : today.weekday;
    return today.subtract(Duration(days: offset));
  }

  DateTime get _weekStart =>
      _sundayOfThisWeek.add(Duration(days: _weekOffset * 7));

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  bool get _isCurrentWeek => _weekOffset == 0;

  String get _rangeLabel {
    final s = _weekStart;
    final e = _weekEnd;
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (s.month == e.month) {
      return '${mo[s.month - 1]} ${s.day} – ${e.day}';
    }
    return '${mo[s.month - 1]} ${s.day} – ${mo[e.month - 1]} ${e.day}';
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  Future<void> _loadWeek() async {
    setState(() => _loading = true);

    if (kIsWeb) {
      setState(() {
        _ironByDay = {};
        _loading = false;
      });
      return;
    }

    final entries =
        await MealStorage.entriesForDateRange(_weekStart, _weekEnd);

    final map = <String, double>{};
    for (final e in entries) {
      final key = _fmt(e.timestamp);
      map[key] = (map[key] ?? 0) + e.iron;
    }

    if (mounted) setState(() { _ironByDay = map; _loading = false; });
  }

  static String _fmt(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadWeek();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final goal = context.watch<FoodTrackerProvider>().goals.iron;

    return Scaffold(
      appBar: AppBar(title: const Text('Iron Progress')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            // ── Week navigation ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous week',
                  onPressed: () {
                    setState(() => _weekOffset--);
                    _loadWeek();
                  },
                ),
                Column(
                  children: [
                    Text(_rangeLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_isCurrentWeek)
                      const Text('This week',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next week',
                  onPressed: _isCurrentWeek
                      ? null
                      : () {
                          setState(() => _weekOffset++);
                          _loadWeek();
                        },
                ),
              ],
            ),

            // ── Goal legend ─────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 2,
                    margin: const EdgeInsets.only(right: 5),
                    color: Colors.orange,
                  ),
                  Text(
                    'Daily goal: ${goal.toStringAsFixed(0)} mg',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Text('Goal met',
                      style: TextStyle(fontSize: 12, color: Colors.green)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Chart ────────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _IronWeekChart(
                      weekStart: _weekStart,
                      ironByDay: _ironByDay,
                      goal: goal,
                      isCurrentWeek: _isCurrentWeek,
                    ),
            ),
            const SizedBox(height: 20),

            // ── Summary stats ────────────────────────────────────────────────
            if (!_loading)
              _SummaryRow(
                weekStart: _weekStart,
                ironByDay: _ironByDay,
                goal: goal,
                isCurrentWeek: _isCurrentWeek,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Iron week line chart ─────────────────────────────────────────────────────

class _IronWeekChart extends StatelessWidget {
  final DateTime weekStart;
  final Map<String, double> ironByDay;
  final double goal;
  final bool isCurrentWeek;

  const _IronWeekChart({
    required this.weekStart,
    required this.ironByDay,
    required this.goal,
    required this.isCurrentWeek,
  });

  static String _fmt(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final primaryColor = Theme.of(context).colorScheme.primary;

    // Build spots from Sunday through today (current week) or Saturday (past week)
    final spots = <FlSpot>[];
    for (int i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      if (isCurrentWeek && day.isAfter(todayDate)) break;
      final iron = ironByDay[_fmt(day)] ?? 0.0;
      spots.add(FlSpot(i.toDouble(), iron));
    }

    final maxVal = spots.fold(goal, (m, s) => s.y > m ? s.y : m);
    final maxY = maxVal * 1.2;
    final yInterval = (goal / 3).ceilToDouble();

    const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY.clamp(goal * 1.1, double.infinity),
        clipData: const FlClipData.all(),

        // ── Line ─────────────────────────────────────────────────────────────
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: primaryColor,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final hitGoal = spot.y >= goal;
                return FlDotCirclePainter(
                  radius: 5,
                  color: hitGoal ? Colors.green : primaryColor,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
          ),
        ],

        // ── Goal dashed line ─────────────────────────────────────────────────
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: goal,
              color: Colors.orange.withOpacity(0.75),
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                labelResolver: (_) => '${goal.toStringAsFixed(0)} mg',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        // ── Touch tooltip ────────────────────────────────────────────────────
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final label = dayLabels[s.x.toInt()];
              final hitGoal = s.y >= goal;
              return LineTooltipItem(
                '$label\n${s.y.toStringAsFixed(1)} mg',
                TextStyle(
                  color: hitGoal ? Colors.green : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),

        // ── Axes ─────────────────────────────────────────────────────────────
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: yInterval,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}mg',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i > 6) return const SizedBox.shrink();
                final day = weekStart.add(Duration(days: i));
                final isFuture = isCurrentWeek && day.isAfter(todayDate);
                final isToday =
                    isCurrentWeek && _fmt(day) == _fmt(todayDate);
                return Text(
                  dayLabels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isToday ? FontWeight.bold : FontWeight.normal,
                    color: isFuture
                        ? Colors.grey.shade400
                        : isToday
                            ? primaryColor
                            : null,
                  ),
                );
              },
            ),
          ),
        ),

        // ── Grid ─────────────────────────────────────────────────────────────
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.grey.withOpacity(0.15),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

// ── Weekly summary row ───────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final DateTime weekStart;
  final Map<String, double> ironByDay;
  final double goal;
  final bool isCurrentWeek;

  const _SummaryRow({
    required this.weekStart,
    required this.ironByDay,
    required this.goal,
    required this.isCurrentWeek,
  });

  static String _fmt(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    double total = 0;
    int daysLogged = 0;
    int daysHitGoal = 0;
    int daysElapsed = 0;

    for (int i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      if (isCurrentWeek && day.isAfter(todayDate)) break;
      daysElapsed++;
      final iron = ironByDay[_fmt(day)] ?? 0.0;
      if (iron > 0) daysLogged++;
      if (iron >= goal) daysHitGoal++;
      total += iron;
    }

    final avg = daysLogged > 0 ? total / daysLogged : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatBox(
            label: 'Avg / day',
            value: '${avg.toStringAsFixed(1)} mg',
          ),
          _StatBox(
            label: 'Days logged',
            value: '$daysLogged / $daysElapsed',
          ),
          _StatBox(
            label: 'Goal met',
            value: '$daysHitGoal / $daysElapsed',
            valueColor: daysHitGoal > 0 ? Colors.green : null,
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatBox({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
