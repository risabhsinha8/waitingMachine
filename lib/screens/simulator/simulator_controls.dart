import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../services/projection_milestones.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../state/simulator_controller.dart';
import '../../theme/app_theme.dart';
import '../../ui/haptics.dart';
import '../../ui/labels.dart';
import '../../utils/units.dart';
import '../../widgets/numeric_entry_dialog.dart';

/// The calorie slider ticks a haptic every this many kcal.
const double _calorieTickStep = 100;

/// Sliders, typed inputs, and activity chips that drive the projection.
class SimulatorControls extends StatelessWidget {
  const SimulatorControls({
    super.key,
    required this.controller,
    required this.onLockIn,
  });

  final SimulatorController controller;
  final VoidCallback onLockIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.loadedFrom case final loaded?) ...[
              _LoadedBanner(
                name: loaded.name,
                onClear: c.clearLoadedPrediction,
              ),
              const SizedBox(height: 12),
            ],
            _WeightSlider(
              key: const Key('start-weight'),
              label: 'Starting weight',
              valueKg: c.startWeightKg,
              unit: c.unit,
              onChanged: c.setStartWeight,
            ),
            const SizedBox(height: 8),
            _LabeledSlider(
              key: const Key('daily-calories'),
              label: 'Daily calorie intake',
              valueText: formatKcal(c.dailyCalories),
              onTapValue: () async {
                final kcal = await showNumericEntryDialog(
                  context,
                  title: 'Daily calorie intake',
                  suffix: 'kcal',
                  initial: c.dailyCalories,
                  min: SimulatorController.minCalories,
                  max: SimulatorController.maxCalories,
                  decimals: 0,
                );
                if (kcal != null) c.setDailyCalories(kcal.roundToDouble());
              },
              slider: Slider(
                value: c.dailyCalories,
                min: SimulatorController.minCalories,
                max: SimulatorController.maxCalories,
                divisions:
                    ((SimulatorController.maxCalories -
                                SimulatorController.minCalories) /
                            SimulatorController.calorieStep)
                        .round(),
                label: formatKcal(c.dailyCalories),
                onChanged: (kcal) {
                  Haptics.tickOnStepCross(
                    c.dailyCalories,
                    kcal,
                    _calorieTickStep,
                  );
                  c.setDailyCalories(kcal);
                },
              ),
            ),
            const SizedBox(height: 12),
            Text('Activity level', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in ActivityLevel.values)
                  ChoiceChip(
                    key: Key('activity-${level.name}'),
                    label: Text(level.label),
                    tooltip: '${level.description} (×${level.multiplier})',
                    selected: c.activityLevel == level,
                    onSelected: (_) => c.setActivityLevel(level),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c.activityLevel.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _TargetSection(controller: c),
            const Divider(height: 24),
            _Summary(controller: c),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('lock-in-button'),
              onPressed: onLockIn,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock In Prediction'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (!AppStateScope.of(context).hasRoomInArena) ...[
              const SizedBox(height: 8),
              Text(
                'Arena full (${AppState.maxActivePredictions}/'
                '${AppState.maxActivePredictions}) · you’ll pick one to '
                'archive',
                key: const Key('lock-in-arena-full'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A title row with a tap-to-type value above a slider.
class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTapValue,
    required this.slider,
  });

  final String label;
  final String valueText;
  final VoidCallback onTapValue;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            TextButton.icon(
              onPressed: onTapValue,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(
                valueText,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ],
        ),
        slider,
      ],
    );
  }
}

/// Weight slider that operates in the user's display unit but reports kg.
class _WeightSlider extends StatelessWidget {
  const _WeightSlider({
    super.key,
    required this.label,
    required this.valueKg,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double valueKg;
  final WeightUnit unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final min = Units.fromKg(
      SimulatorController.minWeightKg,
      unit,
    ).ceilToDouble();
    final max = Units.fromKg(
      SimulatorController.maxWeightKg,
      unit,
    ).floorToDouble();
    final step = unit == WeightUnit.kg ? 0.5 : 1.0;
    final display = Units.fromKg(valueKg, unit).clamp(min, max);
    return _LabeledSlider(
      label: label,
      valueText: Units.format(valueKg, unit),
      onTapValue: () async {
        final value = await showNumericEntryDialog(
          context,
          title: label,
          suffix: unit.wireValue,
          initial: Units.fromKg(valueKg, unit),
          min: min,
          max: max,
        );
        if (value != null) onChanged(Units.toKg(value, unit));
      },
      slider: Slider(
        value: display,
        min: min,
        max: max,
        divisions: ((max - min) / step).round(),
        label: Units.format(valueKg, unit),
        onChanged: (v) {
          // Same round numbers the projection highlights as milestones.
          Haptics.tickOnStepCross(display, v, milestoneStep(unit));
          onChanged(Units.toKg(v, unit));
        },
      ),
    );
  }
}

class _TargetSection extends StatelessWidget {
  const _TargetSection({required this.controller});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final target = c.targetWeightKg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('target-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Target weight'),
          subtitle: const Text('Hold at maintenance once reached'),
          value: target != null,
          onChanged: (on) {
            if (!on) return c.setTargetWeight(null);
            final losing =
                c.points.length > 1 &&
                c.points[1].projectedWeightKg < c.startWeightKg;
            c.setTargetWeight(c.startWeightKg + (losing ? -10 : 5));
          },
        ),
        if (target != null)
          _WeightSlider(
            key: const Key('target-weight'),
            label: 'Target',
            valueKg: target,
            unit: c.unit,
            onChanged: c.setTargetWeight,
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final points = c.points;
    final tdeeNow = points.first.dynamicTdee;
    final balance = c.dailyCalories - tdeeNow;
    final end = points.last;
    final reached = c.targetReachedAt;

    final (
      outcomeLabel,
      outcomeValue,
      outcomeDetail,
    ) = switch (c.targetWeightKg) {
      null => (
        'In ${c.weeks} weeks',
        Units.format(end.projectedWeightKg, c.unit),
        Units.format(
          end.projectedWeightKg - c.startWeightKg,
          c.unit,
          signed: true,
        ),
      ),
      _ when reached != null => (
        'Target by',
        projectionDate.format(reached.date),
        'Week ${reached.weekNumber}',
      ),
      _ => ('Target', 'Not reached', 'in ${c.weeks} weeks'),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Stat(
            label: 'Burn today',
            value: formatKcal(tdeeNow),
            detail: 'TDEE',
          ),
        ),
        Expanded(
          child: _Stat(
            label: balance <= 0 ? 'Deficit' : 'Surplus',
            value: formatKcal(balance.abs()),
            detail: 'per day',
          ),
        ),
        Expanded(
          child: _Stat(
            key: const Key('summary-outcome'),
            label: outcomeLabel,
            value: outcomeValue,
            detail: outcomeDetail,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
        ),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _LoadedBanner extends StatelessWidget {
  const _LoadedBanner({required this.name, required this.onClear});

  final String name;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('loaded-banner'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bookmark, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tweaking “$name”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  'Lock in to save as a new prediction.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Stop tweaking',
            icon: const Icon(Icons.close),
            color: scheme.onSecondaryContainer,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
