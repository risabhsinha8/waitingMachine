import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../ui/haptics.dart';
import '../../ui/keyboard.dart';
import '../../ui/labels.dart';

/// Pinned goal dates (up to three), shown as chips with an add button.
class CheckpointsBar extends StatelessWidget {
  const CheckpointsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final theme = Theme.of(context);
    final checkpoints = app.checkpoints;
    final now = app.now();
    final today = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Checkpoints',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${checkpoints.length} of ${AppState.maxCheckpoints} pinned',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in checkpoints)
                InputChip(
                  key: ValueKey('checkpoint-${c.id}'),
                  avatar: Icon(
                    c.date.isBefore(today)
                        ? Icons.history
                        : Icons.flag_outlined,
                    size: 18,
                  ),
                  label: Text('${c.label} · ${shortDate.format(c.date)}'),
                  deleteButtonTooltipMessage: 'Remove ${c.label}',
                  onDeleted: () => _remove(context, c),
                ),
              if (checkpoints.length < AppState.maxCheckpoints)
                ActionChip(
                  key: const Key('add-checkpoint'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(checkpoints.isEmpty ? 'Pin a goal date' : 'Add'),
                  onPressed: () => _add(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _add(BuildContext context) async {
    final app = AppStateScope.read(context);
    final result = await showDialog<(String, DateTime)>(
      context: context,
      builder: (_) => _CheckpointDialog(today: app.now()),
    );
    if (result == null) return;
    await app.addCheckpoint(result.$1, result.$2);
    Haptics.saved();
  }

  static Future<void> _remove(BuildContext context, Checkpoint c) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    await app.removeCheckpoint(c.id);
    Haptics.deleted();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ‘${c.label}’'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => app.restoreCheckpoint(c),
          ),
        ),
      );
  }
}

class _CheckpointDialog extends StatefulWidget {
  const _CheckpointDialog({required this.today});

  final DateTime today;

  @override
  State<_CheckpointDialog> createState() => _CheckpointDialogState();
}

class _CheckpointDialogState extends State<_CheckpointDialog> {
  static const int _maxLabelLength = 24;

  final _label = TextEditingController();
  DateTime? _date;
  String? _labelError;
  String? _dateError;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    dismissKeyboard(context);
    final today = widget.today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateError = null;
      });
    }
  }

  void _submit() {
    dismissKeyboard(context);
    final label = _label.text.trim();
    setState(() {
      _labelError = label.isEmpty ? 'Name it, e.g. Beach Trip' : null;
      _dateError = _date == null ? 'Pick a date' : null;
    });
    if (_labelError == null && _dateError == null) {
      Navigator.pop(context, (label, _date!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.flag_outlined),
      title: const Text('Pin a goal date'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('checkpoint-label'),
            controller: _label,
            autofocus: true,
            maxLength: _maxLabelLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _pickDate(),
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'Beach Trip, Birthday…',
              errorText: _labelError,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              key: const Key('checkpoint-date'),
              avatar: const Icon(Icons.event, size: 18),
              label: Text(
                _date == null ? 'Choose date' : projectionDate.format(_date!),
              ),
              onPressed: _pickDate,
            ),
          ),
          if (_dateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _dateError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('checkpoint-save'),
          onPressed: _submit,
          child: const Text('Pin'),
        ),
      ],
    );
  }
}
