import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Exposes [AppState] to the widget tree and rebuilds dependents on change.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  /// Reads the state and rebuilds [context] whenever it changes.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStateScope>()!.notifier!;

  /// Reads the state without subscribing, e.g. from callbacks.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppStateScope>()!.notifier!;
}
