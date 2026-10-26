import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../ui/labels.dart';
import 'profile_sheet.dart';

/// Summary of the user's baseline stats; tap to edit them.
class BaselineChip extends StatelessWidget {
  const BaselineChip({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final profile = app.userProfile;
    return ActionChip(
      key: const Key('baseline-chip'),
      avatar: Icon(
        profile == null ? Icons.person_add_alt : Icons.person_outline,
      ),
      label: Text(
        profile == null
            ? 'Set up your profile'
            : '${profile.sex.label} · ${profile.age} y · '
                  '${formatHeight(profile.heightCm, app.unit)}',
      ),
      onPressed: () => showProfileSheet(context),
    );
  }
}

/// Quick kg / lbs switch, persisted to the profile.
class UnitToggle extends StatelessWidget {
  const UnitToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    return SegmentedButton<WeightUnit>(
      key: const Key('unit-toggle'),
      segments: [
        for (final unit in WeightUnit.values)
          ButtonSegment(value: unit, label: Text(unit.wireValue)),
      ],
      selected: {app.unit},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: app.userProfile == null
          ? null
          : (selection) => app.setPreferredUnit(selection.first),
    );
  }
}
