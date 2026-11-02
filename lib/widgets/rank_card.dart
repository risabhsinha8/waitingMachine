import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/bmi_rank.dart';
import '../services/losertown_math.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';
import '../utils/units.dart';
import 'layout.dart';
import 'rank_avatar.dart';

/// The user's rank from their trend weight, or null without a profile or
/// weigh-ins. Pass [excludingLogId] to ask what it was before that weigh-in.
RankStatus? rankStatusOf(AppState app, {String? excludingLogId}) {
  final profile = app.userProfile;
  if (profile == null) return null;
  final logs = [
    for (final l in app.weightLogs)
      if (l.id != excludingLogId) l,
  ];
  final smoothed = LosertownMath.smoothWeights(logs);
  if (smoothed.isEmpty) return null;
  return RankStatus(
    weightKg: smoothed.last.smoothedWeightKg,
    heightCm: profile.heightCm,
  );
}

/// "Lose 2.3 kg to become Elite Ranger", or the equivalent for the top and
/// the side quest.
String nextRankLabel(RankStatus status, WeightUnit unit) {
  final next = status.rank.next;
  final kg = status.kgToNext;
  if (next == null || kg == null) return 'Max level reached. Hold the crown!';
  final amount = Units.format(kg.abs(), unit);
  return status.rank.isSideQuest
      ? 'Gain $amount to return as ${next.title}'
      : 'Lose $amount to become ${next.title}';
}

/// The user's avatar, rank and progress toward the next rank. Tapping it
/// shows the whole ladder. Bounces when the rank goes up.
class RankCard extends StatefulWidget {
  const RankCard({super.key});

  @override
  State<RankCard> createState() => _RankCardState();
}

class _RankCardState extends State<RankCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrate;
  int? _lastLevel;

  @override
  void initState() {
    super.initState();
    _celebrate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _celebrate.dispose();
    super.dispose();
  }

  /// Plays the celebration when [status] ranks up from what was last shown.
  void _watch(RankStatus? status) {
    final level = status?.rank.level;
    final previous = _lastLevel;
    _lastLevel = level;
    if (previous != null && level != null && level > previous) {
      // Not during build: starting it notifies the animated widgets.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _celebrate.forward(from: 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final profile = app.userProfile;
    if (profile == null) return const SizedBox.shrink();
    final status = rankStatusOf(app);
    _watch(status);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rank = status?.rank;
    final accent = rank?.color ?? scheme.outline;

    final eyebrow = switch (rank) {
      null => 'Rank unknown',
      BmiRank(isSideQuest: true) => 'Side quest',
      final r => 'Level ${r.level} of ${BmiRank.maxLevel}',
    };

    return Card(
      key: const Key('rank-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showRankLadderSheet(context),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.16),
                accent.withValues(alpha: 0.02),
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _celebrate,
                builder: (context, child) {
                  // A hop and a wiggle.
                  final t = _celebrate.value;
                  final hop = Curves.easeOut.transform(
                    t < 0.5 ? t * 2 : 2 - t * 2,
                  );
                  return Transform.translate(
                    offset: Offset(0, -14 * hop),
                    child: Transform.scale(scale: 1 + 0.1 * hop, child: child),
                  );
                },
                child: RankAvatar(bmi: status?.bmi, sex: profile.sex, size: 96),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Eyebrow(eyebrow, color: accent)),
                        _LevelUpBadge(animation: _celebrate, color: accent),
                      ],
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        rank?.title ?? 'Mystery Hero',
                        key: ValueKey(rank),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rank?.tagline ??
                          'Step on the scale to reveal your rank. Your trend '
                              'weight decides it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 12),
                      _Progress(status: status, unit: app.unit, color: accent),
                    ],
                    if (profile.age < 18) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Ranks use adult BMI ranges, which don’t fit under-18s.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "LEVEL UP!" that pops in beside the eyebrow during the celebration.
class _LevelUpBadge extends StatelessWidget {
  const _LevelUpBadge({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();
        final opacity = t < 0.8 ? 1.0 : (1 - t) / 0.2;
        return Opacity(
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'LEVEL UP!',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.status,
    required this.unit,
    required this.color,
  });

  final RankStatus status;
  final WeightUnit unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: status.progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    key: const Key('rank-progress'),
                    value: value,
                    minHeight: 8,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'BMI ${status.bmi.toStringAsFixed(1)}',
              key: const Key('rank-bmi'),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          nextRankLabel(status, unit),
          key: const Key('rank-next'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Every rank, top first, with the weight range each covers at the user's
/// height and a marker on where they stand.
Future<void> showRankLadderSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) =>
            _RankLadder(scrollController: scrollController),
      ),
    );

class _RankLadder extends StatelessWidget {
  const _RankLadder({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final profile = app.userProfile;
    if (profile == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final current = rankStatusOf(app)?.rank;

    Widget row(BmiRank rank) => _LadderRow(
      rank: rank,
      heightCm: profile.heightCm,
      unit: app.unit,
      current: rank == current,
    );

    return ListView(
      key: const Key('rank-ladder'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('The Losertown ladder', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Your 7-day trend weight sets your rank. Climb toward the healthy '
          'range to reach the top.',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 16),
        for (final rank in BmiRank.ladder.reversed) row(rank),
        const SizedBox(height: 8),
        const Eyebrow('Side quest'),
        const SizedBox(height: 8),
        row(BmiRank.featherweight),
        const SizedBox(height: 16),
        Text(
          'BMI is a rough guide: it can’t tell muscle from fat, and these '
          'adult ranges don’t apply to under-18s. Ranks are for fun, not a '
          'diagnosis.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.rank,
    required this.heightCm,
    required this.unit,
    required this.current,
  });

  final BmiRank rank;
  final double heightCm;
  final WeightUnit unit;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    String w(double bmi) =>
        Units.format(weightForBmi(bmi, heightCm), unit, decimals: 0);
    final range = switch (rank) {
      BmiRank(maxBmi: double.infinity) => '${w(rank.minBmi)} and up',
      BmiRank(isSideQuest: true) => 'Under ${w(rank.maxBmi)}',
      _ => '${w(rank.minBmi)} – ${w(rank.maxBmi)}',
    };
    final bmiRange = switch (rank) {
      BmiRank(maxBmi: double.infinity) => 'BMI ${rank.minBmi.round()}+',
      BmiRank(isSideQuest: true) => 'BMI under ${rank.maxBmi}',
      _ => 'BMI ${_trim(rank.minBmi)}–${_trim(rank.maxBmi)}',
    };

    return Container(
      key: ValueKey('ladder-${rank.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: current
            ? rank.color.withValues(alpha: 0.14)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: current ? rank.color : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: rank.color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(rank.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rank.isSideQuest ? 'Refuel quest' : 'Level ${rank.level}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: rank.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(rank.title, style: theme.textTheme.titleSmall),
                Text(
                  '$range · $bmiRange',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          if (current)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: rank.color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'You',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}
