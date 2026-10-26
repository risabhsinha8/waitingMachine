import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/keyboard.dart';

/// Asks for a number within [min]..[max]; returns null if cancelled.
Future<double?> showNumericEntryDialog(
  BuildContext context, {
  required String title,
  required String suffix,
  required double initial,
  required double min,
  required double max,
  int decimals = 1,
}) => showDialog<double>(
  context: context,
  builder: (_) => _NumericEntryDialog(
    title: title,
    suffix: suffix,
    initial: initial,
    min: min,
    max: max,
    decimals: decimals,
  ),
);

class _NumericEntryDialog extends StatefulWidget {
  const _NumericEntryDialog({
    required this.title,
    required this.suffix,
    required this.initial,
    required this.min,
    required this.max,
    required this.decimals,
  });

  final String title;
  final String suffix;
  final double initial;
  final double min;
  final double max;
  final int decimals;

  @override
  State<_NumericEntryDialog> createState() => _NumericEntryDialogState();
}

class _NumericEntryDialogState extends State<_NumericEntryDialog> {
  late final TextEditingController _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial.toStringAsFixed(widget.decimals);
    _text = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  void _submit() {
    dismissKeyboard(context);
    final value = double.tryParse(_text.text.trim().replaceAll(',', '.'));
    if (value == null || value < widget.min || value > widget.max) {
      setState(
        () => _error =
            'Enter ${_fmt(widget.min)}–${_fmt(widget.max)} ${widget.suffix}',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: widget.decimals > 0,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          suffixText: widget.suffix,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}
