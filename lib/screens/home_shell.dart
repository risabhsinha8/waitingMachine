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

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  HomeTab _tab = HomeTab.simulator;
  late final SimulatorController _simulator = () {
    final app = AppStateScope.read(context);
    return SimulatorController(app, clock: app.now);
  }();
  final _showLockInFab = ValueNotifier(false);

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
    super.dispose();
  }

  void _select(HomeTab tab) => setState(() => _tab = tab);

  void _viewArena() => _select(HomeTab.arena);

  void _openInSimulator(PredictionSnapshot prediction) {
    _simulator.loadPrediction(prediction);
    _select(HomeTab.simulator);
  }

  @override
  Widget build(BuildContext context) {
    // Wide layouts pin the controls (and their Lock In button) on screen.
    final narrow =
        MediaQuery.sizeOf(context).width < SimulatorScreen.wideBreakpoint;
    return Scaffold(
      // Each tab is its own Scaffold; the FAB lives here so snackbars shown
      // from any tab lift it out of the way.
      body: IndexedStack(
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
      floatingActionButton: _tab == HomeTab.simulator && narrow
          ? LockInFab(
              controller: _simulator,
              visible: _showLockInFab,
              onViewArena: _viewArena,
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => _select(HomeTab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Simulator',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'The Arena',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight_outlined),
            selectedIcon: Icon(Icons.monitor_weight),
            label: 'Weight Log',
          ),
        ],
      ),
    );
  }
}
