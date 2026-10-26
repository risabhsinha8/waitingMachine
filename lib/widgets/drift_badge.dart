import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../theme/app_theme.dart';
import '../ui/labels.dart';

/// Green / amber / red pill for how closely reality tracks a prediction.
class DriftBadge extends StatelessWidget {
  const DriftBadge({super.key, required this.status});

  final AdherenceStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = StatusColors.of(context);
    final (background, foreground, icon) = switch (status) {
      AdherenceStatus.onTrack => (
        colors.good,
        colors.onGood,
        Icons.check_circle,
      ),
      AdherenceStatus.drifting => (
        colors.warn,
        colors.onWarn,
        Icons.trending_flat,
      ),
      AdherenceStatus.offCourse => (colors.bad, colors.onBad, Icons.error),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
