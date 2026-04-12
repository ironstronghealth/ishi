// lib/widgets/floating_nav.dart
import 'package:flutter/material.dart';

class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const FloatingNavBar({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: PhysicalModel(
          color: Theme.of(context).colorScheme.surface,
          elevation: 10,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 64,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // the icons for the pages on the nav bar
                _item(context, Icons.home_rounded, 'Home', 0),
                _item(context, Icons.auto_awesome, 'ISHI-AI Check', 1),
                _item(context, Icons.event, 'Events', 2),
                _item(context, Icons.person, 'Profile', 3), 
                _item(context, Icons.restaurant, 'Food Tracker', 4), // Food tracking page
                _item(context, Icons.info_outline, 'About', 5),
                _donate(context, 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, int index) {
    final cs = Theme.of(context).colorScheme;
    final sel = index == currentIndex;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: sel ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: sel ? cs.primary : cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _donate(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    final sel = index == currentIndex;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onTap(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? cs.primary : cs.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Icon(Icons.favorite, size: 18, color: sel ? cs.onPrimary : cs.onPrimaryContainer),
          const SizedBox(width: 6),
          Text('Donate', style: TextStyle(fontSize: 11, color: sel ? cs.onPrimary : cs.onPrimaryContainer)),
        ]),
      ),
    );
  }
}
