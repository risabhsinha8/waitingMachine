import 'package:flutter/material.dart';

import '../../state/simulator_controller.dart';
import '../../widgets/baseline_chip.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/layout.dart';
import '../../widgets/profile_sheet.dart';
import '../../widgets/quick_log.dart';
import 'lock_in.dart';
import 'projection_list.dart';
import 'simulator_controls.dart';

/// Tab 1: the interactive projection calculator.
class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({
    super.key,
    required this.controller,
    required this.showLockInFab,
    required this.onViewArena,
  });

  /// At or above this width the controls are pinned beside the rows.
  static const double wideBreakpoint = 840;

  final SimulatorController controller;

  /// Set to true while the inline Lock In button is scrolled out of view.
  final ValueNotifier<bool> showLockInFab;
  final VoidCallback onViewArena;

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  static const double _controlsWidth = 420;

  /// Leaves room for the Lock In FAB below the last row.
  static const double _fabClearance = 96;

  /// How much of the controls card's bottom edge (where the inline Lock In
  /// button sits) may scroll off before the FAB takes over.
  static const double _inlineButtonOverlap = 56;

  final _controlsKey = GlobalKey();
  double _controlsHeight = double.infinity;
  final _narrowScroll = ScrollController();

  SimulatorController get _controller => widget.controller;
  late int _loadGeneration;

  @override
  void initState() {
    super.initState();
    _loadGeneration = _controller.loadGeneration;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _narrowScroll.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_controller.loadGeneration == _loadGeneration) return;
    _loadGeneration = _controller.loadGeneration;
    _scrollToControls();
  }

  /// After a saved prediction is loaded (from the sheet or the Arena), brings
  /// the controls and the "Tweaking" banner back into view.
  Future<void> _scrollToControls() async {
    // The card is rebuilt lazily as it scrolls back in, and the banner makes
    // it taller than the list estimated, which can leave the first animation
    // short of the top; a second pass covers the remainder.
    for (var pass = 0; pass < 2; pass++) {
      if (!_narrowScroll.hasClients || _narrowScroll.offset <= 0) break;
      await _narrowScroll.animateTo(
        0,
        duration: Duration(milliseconds: pass == 0 ? 350 : 150),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulator'),
        actions: [
          const QuickLogButton(),
          IconButton(
            key: const Key('saved-predictions-button'),
            tooltip: 'Saved predictions',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => showSavedPredictionsSheet(context, _controller),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(52),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Flexible(child: BaselineChip()),
                SizedBox(width: 8),
                UnitToggle(),
              ],
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.profile == null) {
            return EmptyState(
              icon: Icons.person_outline,
              title: 'Set up your baseline',
              message:
                  'Your sex, age, and height drive the metabolism '
                  'estimate behind every projection.',
              action: FilledButton(
                onPressed: () => showProfileSheet(context),
                child: const Text('Set up profile'),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= SimulatorScreen.wideBreakpoint
                ? _buildWide()
                : _buildNarrow(),
          );
        },
      ),
    );
  }

  Widget _controls() => SimulatorControls(
    key: _controlsKey,
    controller: _controller,
    onLockIn: () =>
        lockInPrediction(context, _controller, onViewArena: widget.onViewArena),
  );

  /// Phone: controls scroll away above the weekly rows.
  Widget _buildNarrow() {
    final points = _controller.points;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        key: const Key('projection-list'),
        controller: _narrowScroll,
        padding: contentPadding(context, bottom: _fabClearance),
        itemCount: points.length + 2,
        itemBuilder: (context, index) => switch (index) {
          0 => _controls(),
          1 => ProjectionHeader(controller: _controller),
          _ => _row(index - 2),
        },
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    // The card is disposed once it scrolls far off-screen, and may not be
    // rebuilt yet while scrolling back, so remember its last known height.
    final box = _controlsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) _controlsHeight = box.size.height;
    widget.showLockInFab.value =
        notification.metrics.pixels > _controlsHeight - _inlineButtonOverlap;
    return false;
  }

  /// Tablet / desktop: controls pinned on the left, rows scroll on the right.
  Widget _buildWide() {
    final points = _controller.points;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _controlsWidth,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
            children: [_controls()],
          ),
        ),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            key: const Key('projection-list'),
            padding: const EdgeInsets.fromLTRB(8, 0, 24, 24),
            itemCount: points.length + 1,
            itemBuilder: (context, index) => index == 0
                ? ProjectionHeader(controller: _controller)
                : _row(index - 1),
          ),
        ),
      ],
    );
  }

  Widget _row(int week) => ProjectionRow(
    key: ValueKey('week-$week'),
    point: _controller.points[week],
    milestone: _controller.milestones[week],
    unit: _controller.unit,
  );
}
