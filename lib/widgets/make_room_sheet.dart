import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';
import '../ui/labels.dart';
import '../utils/units.dart';
import 'series_key.dart';

/// Where a new or restored prediction ended up: in the Arena ([active]),
/// possibly after moving [archived] out to make room, or in the archive.
typedef ArenaRoom = ({bool active, PredictionSnapshot? archived});

/// Makes sure [incomingName] has a place in the Arena. When it's full, asks
/// which prediction to archive, suggesting the one furthest from reality
/// (or the oldest, without weigh-ins), and, if [allowArchive], offers to
/// save straight to the archive instead. Returns null if the user backs out.
Future<ArenaRoom?> makeRoomInArena(
  BuildContext context, {
  required String incomingName,
  required String confirmLabel,
  bool allowArchive = true,
}) async {
  final app = AppStateScope.read(context);
  if (app.hasRoomInArena) return (active: true, archived: null);
  final choice = await showModalBottomSheet<_RoomChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _MakeRoomSheet(
      app: app,
      incomingName: incomingName,
      confirmLabel: confirmLabel,
      allowArchive: allowArchive,
    ),
  );
  switch (choice) {
    case null:
      return null;
    case _SaveToArchive():
      return (active: false, archived: null);
    case _ArchiveOne(:final prediction):
      await app.archivePrediction(prediction.id);
      return (active: true, archived: prediction);
  }
}

sealed class _RoomChoice {
  const _RoomChoice();
}

class _SaveToArchive extends _RoomChoice {
  const _SaveToArchive();
}

class _ArchiveOne extends _RoomChoice {
  const _ArchiveOne(this.prediction);
  final PredictionSnapshot prediction;
}

class _MakeRoomSheet extends StatefulWidget {
  const _MakeRoomSheet({
    required this.app,
    required this.incomingName,
    required this.confirmLabel,
    required this.allowArchive,
  });

  final AppState app;
  final String incomingName;
  final String confirmLabel;
  final bool allowArchive;

  @override
  State<_MakeRoomSheet> createState() => _MakeRoomSheetState();
}

class _MakeRoomSheetState extends State<_MakeRoomSheet> {
  late final Map<String, PredictionEvaluation> _evaluations = {
    for (final e
        in widget.app.evaluation?.byPosition ?? const <PredictionEvaluation>[])
      e.predictionId: e,
  };

  /// Furthest from the trend first; oldest first without weigh-ins.
  late final List<PredictionSnapshot> _candidates =
      [...widget.app.activePredictions]..sort((a, b) {
        final ea = _evaluations[a.id];
        final eb = _evaluations[b.id];
        if (ea != null && eb != null) {
          return eb.deltaFromActualKg.abs().compareTo(
            ea.deltaFromActualKg.abs(),
          );
        }
        return a.createdAt.compareTo(b.createdAt);
      });

  late String _selected = _candidates.first.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final unit = widget.app.unit;
    final suggestion = _evaluations.isEmpty ? 'Oldest' : 'Furthest off';

    return SingleChildScrollView(
      key: const Key('make-room-sheet'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('The Arena is full', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Up to ${AppState.maxActivePredictions} predictions compete at '
            'once. Pick one to archive to make room for '
            '‘${widget.incomingName}’. It keeps its history, and you can '
            'restore it anytime.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          for (final (i, p) in _candidates.indexed)
            _CandidateTile(
              prediction: p,
              evaluation: _evaluations[p.id],
              unit: unit,
              tag: i == 0 ? suggestion : null,
              selected: _selected,
              onSelected: (id) => setState(() => _selected = id),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('make-room-confirm'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.pop(
              context,
              _ArchiveOne(_candidates.firstWhere((p) => p.id == _selected)),
            ),
            child: Text(widget.confirmLabel),
          ),
          if (widget.allowArchive) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('make-room-save-archived'),
              onPressed: () => Navigator.pop(context, const _SaveToArchive()),
              child: Text('Save ‘${widget.incomingName}’ to the archive'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.prediction,
    required this.evaluation,
    required this.unit,
    required this.tag,
    required this.selected,
    required this.onSelected,
  });

  final PredictionSnapshot prediction;
  final PredictionEvaluation? evaluation;
  final WeightUnit unit;
  final String? tag;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = prediction;
    final e = evaluation;
    final slot = p.colorSlot ?? 0;
    final detail = e == null
        ? 'Created ${projectionDate.format(p.createdAt)}'
        : '${e.adherenceStatus.label} · '
              '${Units.formatDifference(e.expectedWeightTodayKg + e.deltaFromActualKg, e.expectedWeightTodayKg, unit, signed: true)}'
              ' vs projected';
    return RadioListTile<String>(
      key: ValueKey('make-room-${p.id}'),
      value: p.id,
      groupValue: selected,
      onChanged: (id) => onSelected(id!),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          SeriesKey(
            color: SeriesColors.of(context, slot),
            dash: seriesDash(slot),
            width: 3,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (tag != null) ...[
            const SizedBox(width: 8),
            Text(
              tag!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${formatKcal(p.dailyCalories)} · ${p.activityLevel.label}\n$detail',
        style: TextStyle(fontFeatures: tabularFigures),
      ),
      isThreeLine: true,
    );
  }
}
