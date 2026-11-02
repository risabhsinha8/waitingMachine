import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';
import '../state/app_state_scope.dart';
import '../ui/haptics.dart';
import '../ui/keyboard.dart';
import '../theme/app_theme.dart';
import '../ui/labels.dart';
import 'confirm_dialog.dart';

Future<void> showProfileSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const ProfileSheet(),
    );

/// Edits sex, age, height, and preferred unit.
class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  static const double _minHeightCm = 100;
  static const double _maxHeightCm = 250;

  final _formKey = GlobalKey<FormState>();
  late Sex _sex;
  late WeightUnit _unit;
  late final TextEditingController _age;
  final _cm = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = AppStateScope.read(context).userProfile;
    _sex = profile?.sex ?? Sex.male;
    _unit = profile?.preferredUnit ?? WeightUnit.kg;
    _age = TextEditingController(text: profile?.age.toString() ?? '');
    if (profile != null) _fillHeight(profile.heightCm);
  }

  @override
  void dispose() {
    for (final c in [_age, _cm, _feet, _inches]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fillHeight(double cm) {
    _cm.text = cm.round().toString();
    final totalInches = (cm / cmPerInch).round();
    _feet.text = (totalInches ~/ 12).toString();
    _inches.text = (totalInches % 12).toString();
  }

  /// Height in cm from whichever fields are showing, or null if incomplete.
  double? _parseHeightCm() {
    if (_unit == WeightUnit.kg) return double.tryParse(_cm.text);
    final feet = int.tryParse(_feet.text);
    final inches = double.tryParse(_inches.text.isEmpty ? '0' : _inches.text);
    if (feet == null || inches == null) return null;
    return (feet * 12 + inches) * cmPerInch;
  }

  void _switchUnit(WeightUnit unit) {
    final cm = _parseHeightCm();
    setState(() {
      _unit = unit;
      if (cm != null) _fillHeight(cm);
    });
  }

  String? _validateHeight(String? _) {
    final cm = _parseHeightCm();
    if (cm == null) return 'Required';
    if (cm < _minHeightCm || cm > _maxHeightCm) {
      return _unit == WeightUnit.kg
          ? 'Enter ${_minHeightCm.round()}–${_maxHeightCm.round()} cm'
          : 'Enter 3′4″–8′2″';
    }
    return null;
  }

  Future<void> _save() async {
    dismissKeyboard(context);
    if (!_formKey.currentState!.validate()) return;
    await AppStateScope.read(context).setUserProfile(
      UserProfile(
        heightCm: _parseHeightCm()!,
        age: int.parse(_age.text),
        sex: _sex,
        preferredUnit: _unit,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _resetAll() async {
    dismissKeyboard(context);
    final app = AppStateScope.read(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset all data?',
      message:
          'This permanently deletes your profile, '
          '${app.predictions.length} predictions, '
          '${app.weightLogs.length} weigh-ins and '
          '${app.checkpoints.length} checkpoints. It can\'t be undone.',
      confirmLabel: 'Reset everything',
      destructive: true,
    );
    if (!confirmed) return;
    await app.resetAll();
    Haptics.deleted();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('All data cleared')));
  }

  /// Whether this is the first-launch setup rather than an edit.
  late final bool _firstRun = AppStateScope.read(context).userProfile == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_firstRun) ...[const _Welcome(), const SizedBox(height: 24)],
              Text('Your baseline', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Used to estimate your metabolism (Mifflin-St Jeor).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<Sex>(
                segments: [
                  for (final sex in Sex.values)
                    ButtonSegment(value: sex, label: Text(sex.label)),
                ],
                selected: {_sex},
                onSelectionChanged: (s) => setState(() => _sex = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('profile-age'),
                controller: _age,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  suffixText: 'years',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                validator: (v) {
                  final age = int.tryParse(v ?? '');
                  if (age == null) return 'Required';
                  if (age < 13 || age > 100) return 'Enter 13–100';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_unit == WeightUnit.kg)
                TextFormField(
                  key: const Key('profile-height-cm'),
                  controller: _cm,
                  decoration: const InputDecoration(
                    labelText: 'Height',
                    suffixText: 'cm',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: _validateHeight,
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('profile-height-ft'),
                        controller: _feet,
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          suffixText: 'ft',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        validator: _validateHeight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('profile-height-in'),
                        controller: _inches,
                        decoration: const InputDecoration(suffixText: 'in'),
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Weight unit',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  SegmentedButton<WeightUnit>(
                    segments: [
                      for (final unit in WeightUnit.values)
                        ButtonSegment(value: unit, label: Text(unit.wireValue)),
                    ],
                    selected: {_unit},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _switchUnit(s.first),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('profile-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_firstRun ? 'Get started' : 'Save'),
              ),
              if (!_firstRun) ...[
                const Divider(height: 40),
                Text('Your data', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Everything is stored only on this device, in this '
                  'browser. Nothing is sent anywhere.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('reset-all'),
                  onPressed: _resetAll,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Reset All Data'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// First-launch intro: what the app does, and what it isn't.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = scheme.onPrimaryContainer;
    Widget step(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome to Losertown',
            style: theme.textTheme.headlineSmall?.copyWith(color: ink),
          ),
          step(Icons.tune, 'Simulate calories and activity'),
          step(Icons.lock_outline, 'Lock in predictions'),
          step(Icons.emoji_events_outlined, 'See which one reality tracks'),
          const SizedBox(height: 16),
          Text(
            'Projections are estimates, not medical advice. Talk to a '
            'doctor before starting a diet.',
            key: const Key('welcome-disclaimer'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: ink.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
