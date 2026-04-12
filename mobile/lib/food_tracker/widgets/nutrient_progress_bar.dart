import 'package:flutter/material.dart';

/// Displays a labeled progress bar for a single nutrient.
///
/// When [progressColors] is supplied (exactly 4 colours) the bar fill is
/// interpolated through those stops at 25 / 50 / 75 / 100 % progress,
/// overriding [color].  Below 25 % the first colour is used.
///
/// When [statusTextColors] is supplied (exactly 3 colours) the consumed/goal
/// label text is coloured according to progress zones:
///   • < 1/3  → statusTextColors[0]
///   • < 90 % → statusTextColors[1]
///   • ≥ 90 % → statusTextColors[2]
class NutrientProgressBar extends StatelessWidget {
  final String label;
  final double consumed;
  final double goal;
  final String unit;
  final Color color;

  /// Optional four-colour ramp applied at the 25 / 50 / 75 / 100 % stops.
  final List<Color>? progressColors;

  /// Optional three-colour status tint for the value label text.
  final List<Color>? statusTextColors;

  const NutrientProgressBar({
    super.key,
    required this.label,
    required this.consumed,
    required this.goal,
    this.unit = 'g',
    this.color = Colors.blue,
    this.progressColors,
    this.statusTextColors,
  });

  /// Piecewise-linear interpolation through four colour stops at
  /// 25 %, 50 %, 75 %, and 100 % progress.
  Color _interpolate(double progress) {
    final cs = progressColors!;
    const stops = [0.25, 0.50, 0.75, 1.00];
    if (progress <= stops[0]) return cs[0];
    if (progress >= stops[3]) return cs[3];
    for (int i = 0; i < stops.length - 1; i++) {
      if (progress <= stops[i + 1]) {
        final t = (progress - stops[i]) / (stops[i + 1] - stops[i]);
        return Color.lerp(cs[i], cs[i + 1], t)!;
      }
    }
    return cs.last;
  }

  /// Returns the status text colour based on three progress zones.
  Color _statusColor(double progress) {
    final cs = statusTextColors!;
    if (progress < 1 / 3) return cs[0]; // low
    if (progress < 0.9) return cs[1];   // mid
    return cs[2];                        // high / full
  }

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (consumed / goal).clamp(0.0, 1.0) : 0.0;
    final remaining = (goal - consumed).clamp(0.0, double.infinity);
    final over = consumed > goal;

    final barColor = (progressColors != null && progressColors!.length == 4)
        ? _interpolate(progress)
        : (over ? Colors.orange : color);

    final labelTextColor = (statusTextColors != null && statusTextColors!.length == 3)
        ? _statusColor(progress)
        : (over ? Colors.orange : Colors.grey[600]!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                over
                    ? '${consumed.toStringAsFixed(1)} / ${goal.toStringAsFixed(0)} $unit  +${(consumed - goal).toStringAsFixed(1)}'
                    : '${consumed.toStringAsFixed(1)} / ${goal.toStringAsFixed(0)} $unit  (${remaining.toStringAsFixed(1)} left)',
                style: TextStyle(
                  fontSize: 12,
                  color: labelTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.black,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}
