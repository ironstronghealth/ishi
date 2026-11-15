import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/meal_entry.dart';
import '../providers/food_tracker_provider.dart';

/// Opens a sheet for copying meals from another day onto the day currently
/// selected in [FoodTrackerProvider] — "same breakfast as yesterday".
Future<void> showCopyMealsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _CopyMealsSheet(),
  );
}

class _CopyMealsSheet extends StatefulWidget {
  const _CopyMealsSheet();

  @override
  State<_CopyMealsSheet> createState() => _CopyMealsSheetState();
}

class _CopyMealsSheetState extends State<_CopyMealsSheet> {
  late final FoodTrackerProvider _provider;
  late final DateTime _target;
  late DateTime _source;

  Map<MealType, List<MealEntry>> _byType = {};
  final Set<MealType> _selected = {};
  bool _loading = true;
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<FoodTrackerProvider>();
    _target = _provider.selectedDate;
    _source = _target.subtract(const Duration(days: 1));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final source = _source;
    final entries = await _provider.entriesOn(source);
    if (!mounted || source != _source) return; // a newer date was picked

    final byType = <MealType, List<MealEntry>>{};
    for (final e in entries) {
      byType.putIfAbsent(e.mealType, () => []).add(e);
    }
    setState(() {
      _byType = byType;
      _selected
        ..clear()
        ..addAll(byType.keys);
      _loading = false;
    });
  }

  Future<void> _pickSource() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _source,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Copy meals from',
    );
    if (picked == null || !mounted) return;
    setState(() => _source = picked);
    await _load();
  }

  List<MealEntry> get _toCopy => [
        for (final type in MealType.values)
          if (_selected.contains(type)) ...?_byType[type],
      ];

  Future<void> _copy() async {
    final entries = _toCopy;
    if (entries.isEmpty || _copying) return;
    setState(() => _copying = true);

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await _provider.copyEntriesToSelectedDate(entries);

    nav.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(
        'Copied ${entries.length} '
        '${entries.length == 1 ? 'item' : 'items'} to ${_dayLabel(_target)}.',
      ),
    ));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'today';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'yesterday';
    return DateFormat('EEE, MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final sameDay = _sameDay(_source, _target);
    final count = sameDay ? 0 : _toCopy.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Copy meals to ${_dayLabel(_target)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('From ${_dayLabel(_source)}')),
                TextButton.icon(
                  onPressed: _copying ? null : _pickSource,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: const Text('Change day'),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sameDay)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Pick a different day to copy from.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else if (_byType.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing was logged on that day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final type in MealType.values)
                      if (_byType.containsKey(type))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(type),
                          onChanged: _copying
                              ? null
                              : (v) => setState(() {
                                    v == true
                                        ? _selected.add(type)
                                        : _selected.remove(type);
                                  }),
                          title: Text(type.label),
                          subtitle: Text(
                            _byType[type]!
                                .map((e) => e.foodItem.name)
                                .join(', '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: count == 0 || _copying || _loading ? null : _copy,
              child: Text(
                count == 0
                    ? 'Copy'
                    : 'Copy $count ${count == 1 ? 'item' : 'items'}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
