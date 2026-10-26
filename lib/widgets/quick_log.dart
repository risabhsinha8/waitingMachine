import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../utils/units.dart';
import 'weight_entry_form.dart';

/// The `+` AppBar action shared by every tab.
class QuickLogButton extends StatelessWidget {
  const QuickLogButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('quick-log-button'),
      tooltip: 'Log weight',
      icon: const Icon(Icons.add),
      onPressed: () => showQuickLogSheet(context),
    );
  }
}

Future<void> showQuickLogSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Log weight',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            WeightEntryForm(
              autofocus: true,
              onSaved: (log) {
                Navigator.pop(sheetContext);
                showLoggedSnackBar(context, log);
              },
            ),
          ],
        ),
      ),
    );

/// Confirms a weigh-in with an Undo that removes it again.
void showLoggedSnackBar(BuildContext context, WeightLog log) {
  final app = AppStateScope.read(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Logged ${Units.format(log.weightKg, app.unit)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => app.deleteWeightLog(log.id),
        ),
      ),
    );
}
