import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/losertown_math.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../state/simulator_controller.dart';
import '../../theme/app_theme.dart';
import '../../ui/haptics.dart';
import '../../ui/keyboard.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/make_room_sheet.dart';
import '../../widgets/series_key.dart';

/// Asks for a name and saves the simulator's current inputs as a prediction.
Future<void> lockInPrediction(
  BuildContext context,
  SimulatorController c, {
  required VoidCallback onViewArena,
}) async {
  final app = AppStateScope.read(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => LockInDialog(
      suggestedName: c.loadedFrom != null
          ? '${c.loadedFrom!.name} (tweaked)'
          : '${formatKcal(c.dailyCalories)} · ${c.activityLevel.label}',
      summary: _summary(c),
      similarTo: findOverlappingPrediction(
        app.activePredictions,
        dailyCalories: c.dailyCalories,
        activityLevel: c.activityLevel,
        startWeightKg: c.startWeightKg,
        targetWeightKg: c.targetWeightKg,
        on: app.now(),
      ),
      arenaFull: !app.hasRoomInArena,
    ),
  );
  if (name == null || !context.mounted) return;

  final room = await makeRoomInArena(
    context,
    incomingName: name,
    confirmLabel: 'Archive & lock in',
  );
  if (room == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  await app.addPrediction(
    name: name,
    dailyCalories: c.dailyCalories,
    activityLevel: c.activityLevel,
    startWeightKg: c.startWeightKg,
    targetWeightKg: c.targetWeightKg,
    weeks: c.weeks,
    archived: !room.active,
  );
  c.clearLoadedPrediction();
  Haptics.saved();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(switch (room) {
          (active: false, archived: _) => 'Saved “$name” to the archive',
          (active: true, archived: final out?) =>
            'Locked in “$name” · ‘${out.name}’ archived',
          _ => 'Locked in “$name”',
        }),
        action: SnackBarAction(label: 'View', onPressed: onViewArena),
      ),
    );
}

/// An Arena prediction whose line would sit on top of a new one with these
/// rules: same activity, calories within 50 kcal, the same target (if any),
/// and projecting within 1 kg of [startWeightKg] on [on].
PredictionSnapshot? findOverlappingPrediction(
  List<PredictionSnapshot> predictions, {
  required double dailyCalories,
  required ActivityLevel activityLevel,
  required double startWeightKg,
  required double? targetWeightKg,
  required DateTime on,
}) {
  for (final p in predictions) {
    final t = p.targetWeightKg;
    final sameTarget =
        (t == null && targetWeightKg == null) ||
        (t != null &&
            targetWeightKg != null &&
            (t - targetWeightKg).abs() <= 1);
    if (p.activityLevel == activityLevel &&
        (p.dailyCalories - dailyCalories).abs() <= 50 &&
        sameTarget &&
        (LosertownMath.expectedWeightOn(p, on) - startWeightKg).abs() <= 1) {
      return p;
    }
  }
  return null;
}

String _summary(SimulatorController c) {
  final parts = [
    '${formatKcal(c.dailyCalories)}/day',
    c.activityLevel.label,
    'from ${Units.format(c.startWeightKg, c.unit)}',
    if (c.targetWeightKg != null)
      'target ${Units.format(c.targetWeightKg!, c.unit)}',
  ];
  final end = c.points.last;
  return '${parts.join(' · ')}\n'
      'Week ${end.weekNumber}: ${Units.format(end.projectedWeightKg, c.unit)}';
}

/// Floating Lock In button, shown once the inline one has scrolled away so
/// it never covers the simulator controls.
class LockInFab extends StatelessWidget {
  const LockInFab({
    super.key,
    required this.controller,
    required this.visible,
    required this.onViewArena,
  });

  final SimulatorController controller;
  final ValueListenable<bool> visible;
  final VoidCallback onViewArena;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, visible]),
      builder: (context, _) {
        final show = visible.value && controller.profile != null;
        return IgnorePointer(
          ignoring: !show,
          child: AnimatedScale(
            scale: show ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: FloatingActionButton.extended(
              key: const Key('lock-in-fab'),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock In Prediction'),
              onPressed: () => lockInPrediction(
                context,
                controller,
                onViewArena: onViewArena,
              ),
            ),
          ),
        );
      },
    );
  }
}

class LockInDialog extends StatefulWidget {
  const LockInDialog({
    super.key,
    required this.suggestedName,
    required this.summary,
    this.similarTo,
    this.arenaFull = false,
  });

  final String suggestedName;
  final String summary;

  /// An Arena prediction this one would overlap, worth a heads-up.
  final PredictionSnapshot? similarTo;

  /// Whether saving will first ask which prediction to archive.
  final bool arenaFull;

  @override
  State<LockInDialog> createState() => _LockInDialogState();
}

class _LockInDialogState extends State<LockInDialog> {
  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.suggestedName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.suggestedName.length,
      );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    dismissKeyboard(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: const Text('Lock in prediction'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('lock-in-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Strict 1600 kcal',
              errorText: _error,
            ),
          ),
          if (widget.similarTo case final similar?) ...[
            const SizedBox(height: 12),
            _Note(
              key: const Key('lock-in-similar'),
              icon: Icons.content_copy_outlined,
              text:
                  'Nearly identical to ‘${similar.name}’ — the two lines '
                  'will overlap in the Arena.',
            ),
          ],
          if (widget.arenaFull) ...[
            const SizedBox(height: 12),
            const _Note(
              key: Key('lock-in-full-note'),
              icon: Icons.inventory_2_outlined,
              text:
                  'The Arena is full (${AppState.maxActivePredictions}/'
                  '${AppState.maxActivePredictions}). Next you’ll pick one '
                  'to archive, or save this one to the archive.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('lock-in-save'),
          onPressed: _submit,
          child: const Text('Lock in'),
        ),
      ],
    );
  }
}

/// Lists saved predictions so one can be loaded into the simulator or cloned.
Future<void> showSavedPredictionsSheet(
  BuildContext context,
  SimulatorController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    minChildSize: 0.3,
    maxChildSize: 0.95,
    builder: (context, scrollController) => _SavedPredictionsList(
      controller: controller,
      scrollController: scrollController,
    ),
  ),
);

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedPredictionsList extends StatelessWidget {
  const _SavedPredictionsList({
    required this.controller,
    required this.scrollController,
  });

  final SimulatorController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final theme = Theme.of(context);
    final active = app.activePredictions.reversed.toList();
    final archived = app.archivedPredictions;
    final rows = <Widget>[
      if (active.isNotEmpty)
        _SectionLabel(
          'In the Arena · ${active.length}/${AppState.maxActivePredictions}',
        ),
      for (final p in active) _tile(context, app, p),
      if (archived.isNotEmpty) _SectionLabel('Archived · ${archived.length}'),
      for (final p in archived) _tile(context, app, p),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Saved predictions', style: theme.textTheme.titleLarge),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(
                  icon: Icons.bookmark_border,
                  title: 'Nothing locked in yet',
                  message:
                      'Tune the simulator, then tap Lock In Prediction '
                      'to save it here.',
                )
              : ListView(
                  controller: scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: rows,
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, AppState app, PredictionSnapshot p) =>
      _SavedPredictionTile(
        prediction: p,
        unit: app.unit,
        onLoad: () {
          controller.loadPrediction(p);
          Navigator.pop(context);
        },
        onClone: () => _clone(context, app, p),
      );

  static Future<void> _clone(
    BuildContext context,
    AppState app,
    PredictionSnapshot p,
  ) async {
    final name = '${p.name} (copy)';
    final room = await makeRoomInArena(
      context,
      incomingName: name,
      confirmLabel: 'Archive & clone',
    );
    if (room == null) return;
    await app.clonePrediction(p.id, name: name, archived: !room.active);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SavedPredictionTile extends StatelessWidget {
  const _SavedPredictionTile({
    required this.prediction,
    required this.unit,
    required this.onLoad,
    required this.onClone,
  });

  final PredictionSnapshot prediction;
  final WeightUnit unit;
  final VoidCallback onLoad;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final slot = p.colorSlot;
    return ListTile(
      key: ValueKey('saved-${p.id}'),
      contentPadding: const EdgeInsets.only(left: 24, right: 16),
      title: Row(
        children: [
          if (slot != null) ...[
            SeriesKey(
              color: SeriesColors.of(context, slot),
              dash: seriesDash(slot),
              width: 3,
              length: 16,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      subtitle: Text(
        '${formatKcal(p.dailyCalories)} · ${p.activityLevel.label}\n'
        'From ${Units.format(p.startWeightKg, unit)} · '
        '${projectionDate.format(p.createdAt)}',
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Clone',
            icon: const Icon(Icons.copy_outlined),
            onPressed: onClone,
          ),
          FilledButton.tonal(onPressed: onLoad, child: const Text('Load')),
        ],
      ),
    );
  }
}
