import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'state/app_state.dart';
import 'state/app_state_scope.dart';
import 'theme/app_theme.dart';
import 'ui/keyboard.dart';

class LosertownApp extends StatelessWidget {
  const LosertownApp({super.key, required this.appState, this.reminderTaps});

  final AppState appState;

  /// Ticks when the user opens a weigh-in reminder; see [HomeShell].
  final ValueListenable<int>? reminderTaps;

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: appState,
      child: MaterialApp(
        title: 'Losertown',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        // Wraps every route, dialog and sheet: tapping empty space hides the
        // keyboard.
        builder: (context, child) => DismissKeyboardOnTap(child: child!),
        home: HomeShell(reminderTaps: reminderTaps),
      ),
    );
  }
}
