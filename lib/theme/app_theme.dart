import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color seed = Color(0xFF00897B);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Corner radius for cards and other large surfaces.
  static const double cardRadius = 24;

  /// Content never stretches wider than this on tablets and desktops.
  static const double maxContentWidth = 720;

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    // ThemeData only fills in font sizes when the theme is localized, so add
    // them here: styles handed straight to components (the app bar title,
    // nav labels) would otherwise fall back to 14px.
    final sized = Typography.englishLike2021.merge(base.textTheme);
    final text = sized.copyWith(
      headlineMedium: sized.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: sized.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: sized.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: sized.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: sized.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: sized.labelSmall?.copyWith(letterSpacing: 0.3),
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [light ? StatusColors.light : StatusColors.dark],
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: light ? 0.6 : 0.3),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: rounded,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: rounded),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      sliderTheme: const SliderThemeData(
        showValueIndicator: ShowValueIndicator.never,
        // The 2024 Material slider: a bar handle and a thicker track.
        // ignore: deprecated_member_use
        year2023: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        labelType: NavigationRailLabelType.all,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 640),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Green / amber / red for drift status, which Material's scheme lacks.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.good,
    required this.onGood,
    required this.warn,
    required this.onWarn,
    required this.bad,
    required this.onBad,
  });

  static const light = StatusColors(
    good: Color(0xFFC6F0CF),
    onGood: Color(0xFF0B5326),
    warn: Color(0xFFFFE2A3),
    onWarn: Color(0xFF5C4300),
    bad: Color(0xFFFFDAD6),
    onBad: Color(0xFF93000A),
  );

  static const dark = StatusColors(
    good: Color(0xFF1C4D2A),
    onGood: Color(0xFFB2EFBF),
    warn: Color(0xFF4F3B00),
    onWarn: Color(0xFFFFDF99),
    bad: Color(0xFF7A1A16),
    onBad: Color(0xFFFFDAD6),
  );

  final Color good;
  final Color onGood;
  final Color warn;
  final Color onWarn;
  final Color bad;
  final Color onBad;

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>()!;

  @override
  StatusColors copyWith({
    Color? good,
    Color? onGood,
    Color? warn,
    Color? onWarn,
    Color? bad,
    Color? onBad,
  }) => StatusColors(
    good: good ?? this.good,
    onGood: onGood ?? this.onGood,
    warn: warn ?? this.warn,
    onWarn: onWarn ?? this.onWarn,
    bad: bad ?? this.bad,
    onBad: onBad ?? this.onBad,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      good: Color.lerp(good, other.good, t)!,
      onGood: Color.lerp(onGood, other.onGood, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      onWarn: Color.lerp(onWarn, other.onWarn, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      onBad: Color.lerp(onBad, other.onBad, t)!,
    );
  }
}

/// Categorical series colors for charts, in fixed slot order (never cycled).
/// Light and dark are the same eight hues stepped for each surface; both sets
/// were validated for colorblind separation against the card surfaces.
abstract final class SeriesColors {
  static const List<Color> _light = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF6250D6), // violet
    Color(0xFFE34948), // red
  ];

  static const List<Color> _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];

  static int get slotCount => _light.length;

  /// Color for [slot]; slots past the palette share a neutral "other" gray.
  static Color of(BuildContext context, int slot) {
    final theme = Theme.of(context);
    if (slot >= slotCount) return theme.colorScheme.outline;
    return (theme.brightness == Brightness.light ? _light : _dark)[slot];
  }
}

/// Tabular figures keep numbers from jittering while sliders are dragged.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];
