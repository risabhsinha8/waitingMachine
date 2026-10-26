import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';
import '../state/simulator_controller.dart';
import '../widgets/profile_sheet.dart';
import '../models/app_models.dart';
import 'arena/arena_screen.dart';
import 'simulator/lock_in.dart';
import 'simulator/simulator_screen.dart';
import 'weight_log_screen.dart';

enum HomeTab { simulator, arena, weightLog }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// At or above this width the tabs move into a side rail.
  static const double railBreakpoint = 840;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  /// Width the side rail takes from the tabs (rail plus divider).
  static const double _railWidth = 81;

  HomeTab _tab = HomeTab.simulator;
  late final SimulatorController _simulator = () {
    final app = AppStateScope.read(context);
    return SimulatorController(app, clock: app.now);
  }();
  final _showLockInFab = ValueNotifier(false);

  /// Fades each tab in as it's selected; tabs keep their state underneath.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  static const _destinations = [
    (icon: Icons.tune_outlined, selectedIcon: Icons.tune, label: 'Simulator'),
    (
      icon: Icons.emoji_events_outlined,
      selectedIcon: Icons.emoji_events,
      label: 'The Arena',
    ),
    (
      icon: Icons.monitor_weight_outlined,
      selectedIcon: Icons.monitor_weight,
      label: 'Weight Log',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppStateScope.read(context).userProfile == null) {
        showProfileSheet(context);
      }
    });
  }

  @override
  void dispose() {
    _simulator.dispose();
    _showLockInFab.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _select(HomeTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _fade.forward(from: 0);
  }

  void _viewArena() => _select(HomeTab.arena);

  void _openInSimulator(PredictionSnapshot prediction) {
    _simulator.loadPrediction(prediction);
    _select(HomeTab.simulator);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final rail = width >= HomeShell.railBreakpoint;
    // Wide simulators pin the controls (and their Lock In button) on screen.
    final narrowSimulator =
        width - (rail ? _railWidth : 0) < SimulatorScreen.wideBreakpoint;

    final tabs = FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
      child: IndexedStack(
        index: _tab.index,
        children: [
          SimulatorScreen(
            controller: _simulator,
            showLockInFab: _showLockInFab,
            onViewArena: _viewArena,
          ),
          ArenaScreen(
            onCreatePrediction: () => _select(HomeTab.simulator),
            onOpenInSimulator: _openInSimulator,
          ),
          const WeightLogScreen(),
        ],
      ),
    );

    return Scaffold(
      // Each tab is its own Scaffold; the FAB lives here so snackbars shown
      // from any tab lift it out of the way.
      body: rail
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab.index,
                  onDestinationSelected: (i) => _select(HomeTab.values[i]),
                  groupAlignment: -0.85,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 16),
                    child: _Logo(),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: tabs),
              ],
            )
          : tabs,
      floatingActionButton: _tab == HomeTab.simulator && narrowSimulator
          ? LockInFab(
              controller: _simulator,
              visible: _showLockInFab,
              onViewArena: _viewArena,
            )
          : null,
      bottomNavigationBar: rail
          ? null
          : NavigationBar(
              selectedIndex: _tab.index,
              onDestinationSelected: (i) => _select(HomeTab.values[i]),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}

/// The app mark at the top of the side rail.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Losertown',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.trending_down, color: scheme.onPrimary),
      ),
    );
  }
}
