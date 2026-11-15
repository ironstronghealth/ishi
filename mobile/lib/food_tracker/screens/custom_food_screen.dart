import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/food_item.dart';
import '../providers/food_tracker_provider.dart';
import '../services/barcode_service.dart';

/// Form for entering a food by hand from its nutrition label.
///
/// Pops with the saved [FoodItem]. When [barcode] is supplied (a scan that
/// found nothing) the food is saved against it, so the next scan of that
/// package finds it.
class CustomFoodScreen extends StatefulWidget {
  /// Existing custom food to edit; null creates a new one.
  final FoodItem? existing;
  final String? barcode;

  const CustomFoodScreen({super.key, this.existing, this.barcode});

  @override
  State<CustomFoodScreen> createState() => _CustomFoodScreenState();
}

class _CustomFoodScreenState extends State<CustomFoodScreen> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _servingLabel;
  late final TextEditingController _servingGrams;
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _iron;
  late final TextEditingController _barcode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    String numText(double? v) => v == null ? '' : _fmt(v);

    _name = TextEditingController(text: f?.name ?? '');
    _brand = TextEditingController(text: f?.brand ?? '');
    _servingLabel = TextEditingController(
      text: (f != null && f.portions.isNotEmpty) ? f.portions.first.label : '',
    );
    _servingGrams = TextEditingController(text: numText(f?.servingSize));
    _calories = TextEditingController(text: numText(f?.calories));
    _protein = TextEditingController(text: numText(f?.protein));
    _carbs = TextEditingController(text: numText(f?.carbs));
    _fat = TextEditingController(text: numText(f?.fat));
    _iron = TextEditingController(text: numText(f?.iron));

    final storedBarcode = f == null
        ? null
        : context.read<FoodTrackerProvider>().barcodeFor(f.id);
    _barcode = TextEditingController(text: widget.barcode ?? storedBarcode ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name, _brand, _servingLabel, _servingGrams, _calories, //
      _protein, _carbs, _fat, _iron, _barcode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  static double? _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final grams = _parse(_servingGrams.text)!;
    final label = _servingLabel.text.trim();
    final brand = _brand.text.trim();
    final barcode = _barcode.text.trim();

    final food = FoodItem(
      id: widget.existing?.id ?? 'custom_${_uuid.v4()}',
      name: _name.text.trim(),
      brand: brand.isEmpty ? null : brand,
      servingSize: grams,
      // Values are entered per serving, matching how labels print them.
      calories: _parse(_calories.text) ?? 0,
      protein: _parse(_protein.text) ?? 0,
      carbs: _parse(_carbs.text) ?? 0,
      fat: _parse(_fat.text) ?? 0,
      iron: _parse(_iron.text) ?? 0,
      portions: label.isEmpty
          ? const []
          : [FoodPortion(label: label, grams: grams)],
    );

    await context
        .read<FoodTrackerProvider>()
        .saveCustomFood(food, barcode: barcode.isEmpty ? null : barcode);

    if (mounted) Navigator.pop(context, food);
  }

  // ── Validators ─────────────────────────────────────────────────────────────

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _positive(String? v) {
    final n = _parse(v ?? '');
    if (n == null) return 'Enter a number';
    if (n <= 0) return 'Must be above 0';
    if (n > 5000) return 'Too large';
    return null;
  }

  /// Empty is allowed (treated as 0); anything typed must be a sane number.
  String? _optionalAmount(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = _parse(v);
    if (n == null) return 'Enter a number';
    if (n < 0) return 'Cannot be negative';
    if (n > 10000) return 'Too large';
    return null;
  }

  String? _barcodeValidator(String? v) {
    final code = (v ?? '').trim();
    if (code.isEmpty || BarcodeService.isValidBarcode(code)) return null;
    return 'Barcodes are 8, 12, 13 or 14 digits';
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Food' : 'Create Food')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.barcode != null && !isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'No product was found for barcode ${widget.barcode}. '
                  'Enter the nutrition label once and it will be recognised '
                  'next time you scan it.',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            _field(_name, 'Name', validator: _required, text: true),
            _field(_brand, 'Brand (optional)', text: true),
            const SizedBox(height: 8),
            const Text('Serving',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    _servingLabel,
                    'Description (optional)',
                    hint: 'e.g. 1 bar, 2 slices',
                    text: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _field(
                    _servingGrams,
                    'Weight',
                    suffix: 'g',
                    validator: _positive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Nutrition per serving',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _field(_calories, 'Calories',
                suffix: 'kcal', validator: _optionalAmount),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(_protein, 'Protein',
                      suffix: 'g', validator: _optionalAmount),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_carbs, 'Carbs',
                      suffix: 'g', validator: _optionalAmount),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_fat, 'Fat',
                      suffix: 'g', validator: _optionalAmount),
                ),
              ],
            ),
            _field(
              _iron,
              'Iron',
              suffix: 'mg',
              validator: _optionalAmount,
              helper: 'US labels show iron in mg next to the % Daily Value.',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _barcode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _barcodeValidator,
              decoration: const InputDecoration(
                labelText: 'Barcode (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_scanner),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(isEdit ? 'Save Changes' : 'Save Food'),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? suffix,
    String? hint,
    String? helper,
    String? Function(String?)? validator,
    bool text = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        textCapitalization:
            text ? TextCapitalization.sentences : TextCapitalization.none,
        keyboardType: text
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
