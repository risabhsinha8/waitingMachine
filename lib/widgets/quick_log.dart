import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../utils/units.dart';
import '../ui/haptics.dart';
import 'rank_card.dart';
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

/// Confirms a weigh-in with an Undo that removes it again, and celebrates
/// when it moves the user up a rank.
void showLoggedSnackBar(BuildContext context, WeightLog log) {
  final app = AppStateScope.read(context);
  final before = rankStatusOf(app, excludingLogId: log.id)?.rank;
  final after = rankStatusOf(app)?.rank;
  final levelUp = before != null && after != null && after.level > before.level;
  if (levelUp) Haptics.levelUp();
  final logged = 'Logged ${Units.format(log.weightKg, app.unit)}';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: levelUp
            ? Row(
                children: [
                  Icon(after.icon, color: after.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Level up! You’re now ${after.title} · $logged',
                      key: const Key('level-up-message'),
                    ),
                  ),
                ],
              )
            : Text(logged),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => app.deleteWeightLog(log.id),
        ),
      ),
    );
}
