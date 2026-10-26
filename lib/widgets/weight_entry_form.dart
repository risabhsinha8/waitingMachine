import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';
import '../ui/haptics.dart';
import '../ui/keyboard.dart';
import '../utils/units.dart';

/// Date + big weight input + one-tap Save. Prefills the latest weigh-in so a
/// typical log is a nudge of the stepper and a tap.
class WeightEntryForm extends StatefulWidget {
  const WeightEntryForm({
    super.key,
    required this.onSaved,
    this.autofocus = false,
  });

  final ValueChanged<WeightLog> onSaved;
  final bool autofocus;

  @override
  State<WeightEntryForm> createState() => _WeightEntryFormState();
}

class _WeightEntryFormState extends State<WeightEntryForm> {
  static const double _minKg = 30;
  static const double _maxKg = 300;
  static final DateFormat _dayFormat = DateFormat('EEE, MMM d');

  final _weight = TextEditingController();

  /// Null means "today", resolved at save time.
  DateTime? _pickedDay;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = AppStateScope.read(context);
    final latest = app.latestLoggedWeightKg;
    if (latest != null) _setText(Units.fromKg(latest, app.unit));
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  void _setText(double value) {
    final text = value.toStringAsFixed(1);
    _weight.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
  }

  double? _parse() => double.tryParse(_weight.text.trim().replaceAll(',', '.'));

  void _nudge(double delta) {
    final current = _parse();
    if (current == null) return;
    setState(() {
      _setText(current + delta);
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    dismissKeyboard(context);
    final today = AppStateScope.read(context).now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDay ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (picked == null) return;
    setState(
      () => _pickedDay = DateUtils.isSameDay(picked, today) ? null : picked,
    );
  }

  Future<void> _save() async {
    dismissKeyboard(context);
    final app = AppStateScope.read(context);
    final value = _parse();
    final kg = value == null ? null : Units.toKg(value, app.unit);
    if (kg == null || kg < _minKg || kg > _maxKg) {
      setState(
        () => _error =
            'Enter ${Units.format(_minKg, app.unit, decimals: 0)}–'
            '${Units.format(_maxKg, app.unit, decimals: 0)}',
      );
      return;
    }
    setState(() => _saving = true);
    final picked = _pickedDay;
    // Past days are stamped at midday so time zones can't shift the date.
    final date = picked == null
        ? app.now()
        : DateTime(picked.year, picked.month, picked.day, 12);
    final log = await app.addWeightLog(kg, date: date);
    Haptics.saved();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = null;
      _pickedDay = null;
    });
    widget.onSaved(log);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final theme = Theme.of(context);
    final unit = app.unit;
    final step = unit == WeightUnit.kg ? 0.1 : 0.2;
    final day = _pickedDay ?? app.now();
    final sameDay = [
      for (final l in app.weightLogs)
        if (DateUtils.isSameDay(l.date, day)) l,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const Key('log-weight-date'),
            avatar: const Icon(Icons.event, size: 18),
            label: Text(_pickedDay == null ? 'Today' : _dayFormat.format(day)),
            onPressed: _pickDate,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Decrease',
              onPressed: () => _nudge(-step),
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('log-weight-input'),
                controller: _weight,
                autofocus: widget.autofocus,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
                decoration: InputDecoration(
                  hintText: unit == WeightUnit.kg ? '80.0' : '176.0',
                  suffixText: unit.wireValue,
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Increase',
              onPressed: () => _nudge(step),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (sameDay.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Already logged ${Units.format(sameDay.last.weightKg, unit)} '
            '${_pickedDay == null ? 'today' : 'that day'}; '
            'same-day weigh-ins are averaged.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('log-weight-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('Save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    );
  }
}
