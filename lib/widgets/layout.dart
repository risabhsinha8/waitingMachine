import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Horizontal padding that centers scrolling content in a column no wider
/// than [AppTheme.maxContentWidth], with at least [gutter] on each side.
EdgeInsets contentPadding(
  BuildContext context, {
  double gutter = 16,
  double top = 8,
  double bottom = 24,
  double maxWidth = AppTheme.maxContentWidth,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = ((width - maxWidth) / 2).clamp(gutter, double.infinity);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// A section title with optional trailing detail, used between cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 28, 4, 12),
  });

  final String title;

  /// Usually a short muted caption; may be any widget.
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ],
      ),
    );
  }
}

/// Muted caption text, for [SectionHeader.trailing] and similar.
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.textAlign});

  final String text;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: tabularFigures,
      ),
    );
  }
}

/// A small uppercase label above a stat ("TREND", "THIS WEEK").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}
