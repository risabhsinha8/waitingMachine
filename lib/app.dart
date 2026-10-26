import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'state/app_state.dart';
import 'state/app_state_scope.dart';
import 'theme/app_theme.dart';
import 'ui/keyboard.dart';

class LosertownApp extends StatelessWidget {
  const LosertownApp({super.key, required this.appState});

  final AppState appState;

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
        home: const HomeShell(),
      ),
    );
  }
}
