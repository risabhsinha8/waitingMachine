import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/checkpoint_forecast.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_theme.dart';
import '../../ui/haptics.dart';
import '../../utils/units.dart';
import '../../widgets/make_room_sheet.dart';
import '../../widgets/quick_log.dart';
import 'archived_predictions.dart';
import 'checkpoints_bar.dart';
import 'prediction_card.dart';
import 'prediction_details_sheet.dart';
import 'timeline_chart.dart';
import 'timeline_hero.dart';

/// Tab 2: the active predictions ranked against reality, with the archive
/// tucked below.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({
    super.key,
    required this.onCreatePrediction,
    required this.onOpenInSimulator,
  });

  final VoidCallback onCreatePrediction;
  final ValueChanged<PredictionSnapshot> onOpenInSimulator;

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  bool _archiveOpen = false;

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final evaluation = app.evaluation;
    final now = app.now();
    final evaluations = {
      for (final e in evaluation?.byPosition ?? const <PredictionEvaluation>[])
        e.predictionId: e,
    };
    final active = app.activePredictions;
    final ranked = _sortedByMatch(active, evaluation);
    final archived = app.archivedPredictions;
    final archivedEvaluations = {
      if (archived.isNotEmpty)
        for (final e
            in app.archivedEvaluation?.byPosition ??
                const <PredictionEvaluation>[])
          e.predictionId: e,
    };

    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TimelineChart(
          predictions: active,
          smoothed: app.smoothedWeights,
          unit: app.unit,
          now: now,
        ),
      ),
      TimelineHero(
        evaluation: evaluation,
        predictions: active,
        archivedCount: archived.length,
        logCount: app.weightLogs.length,
        unit: app.unit,
        now: now,
        onCreatePrediction: widget.onCreatePrediction,
        onLogWeight: () => showQuickLogSheet(context),
      ),
      const CheckpointsBar(),
      if (active.isNotEmpty)
        _ArenaHeader(active: active, ranked: evaluation != null),
      for (final p in ranked)
        _card(context, app, p, evaluations[p.id], evaluation, now),
      if (archived.isNotEmpty) ...[
        ArchiveHeader(
          count: archived.length,
          expanded: _archiveOpen,
          onToggle: () => setState(() => _archiveOpen = !_archiveOpen),
        ),
        if (_archiveOpen)
          for (final p in archived)
            _archivedTile(context, app, p, archivedEvaluations[p.id]),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('The Arena'),
        actions: const [QuickLogButton()],
      ),
      body: ListView.builder(
        key: const Key('arena-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: items.length,
        itemBuilder: (context, index) => items[index],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppState app,
    PredictionSnapshot p,
    PredictionEvaluation? e,
    PredictionMatchResult? evaluation,
    DateTime now,
  ) {
    return Padding(
      key: ValueKey('arena-item-${p.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: _SwipeAction(
        id: p.id,
        label: 'Archive',
        icon: Icons.archive_outlined,
        destructive: false,
        onSwiped: () => _archive(context, p),
        child: PredictionCard(
          key: ValueKey('prediction-card-${p.id}'),
          prediction: p,
          evaluation: e,
          asOf: evaluation?.asOf,
          now: now,
          unit: app.unit,
          canReanchor: app.currentWeightKg != null,
          checkpoints: forecastCheckpoints(
            p,
            app.checkpoints,
            now: now,
            profile: app.userProfile,
            currentWeightKg: app.currentWeightKg,
          ),
          onTap: () => showPredictionDetailsSheet(context, p.id),
          onAction: (action) => _onAction(context, p, action),
        ),
      ),
    );
  }

  Widget _archivedTile(
    BuildContext context,
    AppState app,
    PredictionSnapshot p,
    PredictionEvaluation? e,
  ) {
    return Padding(
      key: ValueKey('arena-item-${p.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: _SwipeAction(
        id: p.id,
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSwiped: () => _delete(context, p),
        child: ArchivedPredictionTile(
          key: ValueKey('archived-tile-${p.id}'),
          prediction: p,
          evaluation: e,
          unit: app.unit,
          onTap: () => showPredictionDetailsSheet(context, p.id),
          onRestore: () => _restore(context, p),
          onAction: (action) => _onAction(context, p, action),
        ),
      ),
    );
  }

  /// Closest expected weight first; newest first when there's nothing to
  /// compare against yet.
  static List<PredictionSnapshot> _sortedByMatch(
    List<PredictionSnapshot> predictions,
    PredictionMatchResult? evaluation,
  ) {
    if (evaluation == null) return predictions.reversed.toList();
    final rank = {
      for (final (i, e) in evaluation.byPosition.indexed) e.predictionId: i,
    };
    final unranked = rank.length;
    return [...predictions]..sort(
      (a, b) => (rank[a.id] ?? unranked).compareTo(rank[b.id] ?? unranked),
    );
  }

  void _onAction(
    BuildContext context,
    PredictionSnapshot p,
    PredictionAction action,
  ) {
    switch (action) {
      case PredictionAction.reanchor:
        _reanchor(context, p);
      case PredictionAction.openInSimulator:
        widget.onOpenInSimulator(p);
      case PredictionAction.clone:
        _clone(context, p);
      case PredictionAction.archive:
        _archive(context, p);
      case PredictionAction.delete:
        _delete(context, p);
    }
  }

  static Future<void> _delete(
    BuildContext context,
    PredictionSnapshot p,
  ) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final index = app.predictions.indexWhere((x) => x.id == p.id);
    await app.deletePrediction(p.id);
    Haptics.deleted();
    _showUndo(
      messenger,
      'Deleted ‘${p.name}’',
      () => app.restorePrediction(p, index: index),
    );
  }

  static Future<void> _archive(
    BuildContext context,
    PredictionSnapshot p,
  ) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    await app.archivePrediction(p.id);
    Haptics.deleted();
    _showUndo(
      messenger,
      'Archived ‘${p.name}’',
      () => app.restorePrediction(p),
    );
  }

  /// Brings [p] back into the Arena, asking which to swap out if it's full.
  static Future<void> _restore(
    BuildContext context,
    PredictionSnapshot p,
  ) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final room = await makeRoomInArena(
      context,
      incomingName: p.name,
      confirmLabel: 'Swap in ‘${p.name}’',
      allowArchive: false,
    );
    if (room == null) return;
    await app.unarchivePrediction(p.id);
    Haptics.saved();
    final out = room.archived;
    _showUndo(
      messenger,
      out == null
          ? 'Restored ‘${p.name}’ to the Arena'
          : 'Swapped in ‘${p.name}’ · ‘${out.name}’ archived',
      () async {
        await app.restorePrediction(p);
        if (out != null) await app.restorePrediction(out);
      },
    );
  }

  static Future<void> _reanchor(
    BuildContext context,
    PredictionSnapshot p,
  ) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final updated = await app.reanchorPrediction(p.id);
    _showUndo(
      messenger,
      'Re-anchored ‘${p.name}’ to '
      '${Units.format(updated.startWeightKg, app.unit)} today',
      () => app.restorePrediction(p),
    );
  }

  static Future<void> _clone(BuildContext context, PredictionSnapshot p) async {
    final app = AppStateScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = '${p.name} (copy)';
    final room = await makeRoomInArena(
      context,
      incomingName: name,
      confirmLabel: 'Archive & clone',
    );
    if (room == null) return;
    final copy = await app.clonePrediction(
      p.id,
      name: name,
      archived: !room.active,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            room.active
                ? 'Cloned as ‘${copy.name}’'
                : 'Cloned as ‘${copy.name}’ into the archive',
          ),
        ),
      );
  }

  static void _showUndo(
    ScaffoldMessengerState messenger,
    String message,
    VoidCallback onUndo,
  ) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
  }
}

/// Swipe left to archive (active cards) or delete (archived rows); the
/// parent shows an Undo snackbar.
class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.destructive,
    required this.onSwiped,
    required this.child,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback onSwiped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = StatusColors.of(context);
    final background = destructive ? status.bad : scheme.secondary;
    final foreground = destructive ? status.onBad : scheme.onSecondary;
    return Dismissible(
      key: ValueKey('dismiss-$id'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onSwiped(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(destructive ? 16 : 20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: foreground),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: foreground),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// "In the Arena" with a slot meter showing how many of the
/// [AppState.maxActivePredictions] places are taken, in each line's color.
class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({required this.active, required this.ranked});

  final List<PredictionSnapshot> active;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final taken = {for (final p in active) ?p.colorSlot};
    const max = AppState.maxActivePredictions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('In the Arena', style: theme.textTheme.titleMedium),
          const SizedBox(width: 10),
          Semantics(
            key: const Key('arena-slot-meter'),
            label: '${active.length} of $max Arena places used',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var slot = 0; slot < max; slot++)
                  Container(
                    width: 12,
                    height: 6,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: taken.contains(slot)
                          ? SeriesColors.of(context, slot)
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  '${active.length}/$max',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ranked ? 'Closest match first' : 'Newest first',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
