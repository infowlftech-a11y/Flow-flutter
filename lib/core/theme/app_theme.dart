import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';
import 'radii.dart';
import 'typography.dart';

/// Semantic tones that fall outside Material's ColorScheme, tuned per
/// brightness. Read with `context.tones`.
@immutable
class FlowTones extends ThemeExtension<FlowTones> {
  const FlowTones({
    required this.success,
    required this.successTint,
    required this.warning,
    required this.warningTint,
    required this.danger,
    required this.dangerTint,
    required this.card,
    required this.cardHigh,
    required this.line,
    required this.textFaint,
    required this.azureBrand,
    required this.heroGradient,
    required this.brightness,
  });

  final Color success;
  final Color successTint;
  final Color warning;
  final Color warningTint;
  final Color danger;
  final Color dangerTint;

  /// Resting card surface / elevated card surface.
  final Color card;
  final Color cardHigh;

  /// Hairline borders and dividers.
  final Color line;

  /// Tertiary text.
  final Color textFaint;

  /// The brand azure, at the depth each brightness can actually carry.
  ///
  /// Overwhelmingly a *foreground*: pill labels, tile icons, prices, the
  /// "mine" chat bubble. The light theme used the raw logo azure (#1DB0FE)
  /// here, which is a glow colour — as text on a white card it measures 2.4:1
  /// and on its own tinted pill 2.1:1, against 7.5 and 6.0 for the same token
  /// in dark. That gap is why light mode read as washed out next to dark.
  /// The handful of fill usages only gain from the deeper value.
  final Color azureBrand;

  /// Brand gradient for hero surfaces (stat tiles, CTAs' backdrop, gates).
  final Gradient heroGradient;

  /// Which brightness these tones belong to. Read by [onTint].
  final Brightness brightness;

  /// A tone deep enough to read as a *label on a tint of itself*.
  ///
  /// Pills and date blocks paint text in a tone over roughly 14% of the same
  /// tone. On a dark card that lands near 6:1; on white the identical pair
  /// measures 3.6:1, because a 14% tint barely moves white. The fill can stay
  /// where it is — it is the text that has to go deeper, and only in light.
  ///
  /// Measured by test/text_contrast_test.dart against the real render, which
  /// is how the 3.6 was found in the first place.
  Color onTint(Color tone) => brightness == Brightness.dark
      ? tone
      : Color.alphaBlend(const Color(0x47000000), tone);

  static const dark = FlowTones(
    brightness: Brightness.dark,
    success: FlowColors.emerald,
    successTint: Color(0x2617CE92),
    warning: FlowColors.amber,
    warningTint: Color(0x26FFB547),
    danger: FlowColors.coral,
    dangerTint: Color(0x26FF5D72),
    card: FlowColors.navy900,
    cardHigh: FlowColors.navy850,
    line: Color(0x33355C8F),
    textFaint: FlowColors.slate,
    azureBrand: FlowColors.azure,
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0A2C55), Color(0xFF041530)],
    ),
  );

  static const light = FlowTones(
    brightness: Brightness.light,
    success: FlowColors.emeraldDeep,
    successTint: Color(0x1A0B9A6C),
    warning: FlowColors.amberDeep,
    warningTint: Color(0x21FFB547),
    danger: FlowColors.coralDeep,
    dangerTint: Color(0x1AD23B50),
    card: FlowColors.white,
    cardHigh: FlowColors.white,
    line: Color(0x1F0A1B36),
    textFaint: FlowColors.inkFaint,
    azureBrand: FlowColors.azureDeep,
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [FlowColors.ink, Color(0xFF0A2C55)],
    ),
  );

  @override
  FlowTones copyWith({Color? success}) => this;

  /// A real interpolation, not a step.
  ///
  /// The first version returned `t < .5 ? this : other`, which meant that in
  /// any animated theme change Material's ColorScheme cross-faded continuously
  /// while every card, border, tint and pill painted from these tones jumped
  /// at the halfway point — the whole app appeared to pop mid-fade.
  @override
  FlowTones lerp(FlowTones? other, double t) {
    if (other == null) return this;
    return FlowTones(
      // Discrete — flips with the half of the fade it belongs to.
      brightness: t < .5 ? brightness : other.brightness,
      success: Color.lerp(success, other.success, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningTint: Color.lerp(warningTint, other.warningTint, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardHigh: Color.lerp(cardHigh, other.cardHigh, t)!,
      line: Color.lerp(line, other.line, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      azureBrand: Color.lerp(azureBrand, other.azureBrand, t)!,
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
    );
  }
}

extension FlowThemeX on BuildContext {
  FlowTones get tones => Theme.of(this).extension<FlowTones>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

abstract final class FlowTheme {
  // Built once each. `MaterialApp` is handed both themes on every rebuild of
  // the app root, and each call assembled ~25 sub-themes and 15 TextStyles
  // from scratch — then Material compared the result field-by-field against
  // the previous one to decide whether anything had changed. Neither depends
  // on anything but the palette, so both are constants in all but syntax.
  static ThemeData? _darkCache;
  static ThemeData? _lightCache;

  static ThemeData dark() => _darkCache ??= _buildDark();
  static ThemeData light() => _lightCache ??= _buildLight();

  static ThemeData _buildDark() => _build(
        brightness: Brightness.dark,
        tones: FlowTones.dark,
        scheme: const ColorScheme.dark(
          primary: FlowColors.azure,
          onPrimary: FlowColors.ink,
          secondary: FlowColors.azureGlow,
          onSecondary: FlowColors.ink,
          surface: FlowColors.navy950,
          onSurface: FlowColors.mist,
          onSurfaceVariant: FlowColors.haze,
          surfaceContainerLowest: FlowColors.navy950,
          surfaceContainerLow: FlowColors.navy900,
          surfaceContainer: FlowColors.navy900,
          surfaceContainerHigh: FlowColors.navy850,
          surfaceContainerHighest: FlowColors.navy800,
          error: FlowColors.coral,
          onError: FlowColors.ink,
          outline: Color(0x4D355C8F),
          outlineVariant: Color(0x33355C8F),
          inverseSurface: FlowColors.mist,
          onInverseSurface: FlowColors.navy950,
          inversePrimary: FlowColors.azureDeep,
        ),
      );

  static ThemeData _buildLight() => _build(
        brightness: Brightness.light,
        tones: FlowTones.light,
        scheme: const ColorScheme.light(
          primary: FlowColors.azureDeep,
          onPrimary: FlowColors.white,
          secondary: FlowColors.azure,
          onSecondary: FlowColors.ink,
          surface: Color(0xFFF3F6FB),
          onSurface: FlowColors.inkText,
          onSurfaceVariant: FlowColors.inkSub,
          surfaceContainerLowest: Color(0xFFF3F6FB),
          surfaceContainerLow: FlowColors.white,
          surfaceContainer: FlowColors.white,
          surfaceContainerHigh: FlowColors.white,
          surfaceContainerHighest: Color(0xFFE9F0F9),
          error: FlowColors.coralDeep,
          onError: FlowColors.white,
          outline: Color(0x330A1B36),
          outlineVariant: Color(0x1F0A1B36),
          inverseSurface: FlowColors.ink,
          onInverseSurface: FlowColors.mist,
          inversePrimary: FlowColors.azure,
        ),
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required FlowTones tones,
  }) {
    final dark = brightness == Brightness.dark;
    final text = scheme.onSurface;
    final sub = scheme.onSurfaceVariant;

    final textTheme = TextTheme(
      displayLarge: display(40, 780, color: text, spacing: -1.2, height: 1.05),
      displayMedium: display(32, 760, color: text, spacing: -.8, height: 1.1),
      displaySmall: display(26, 740, color: text, spacing: -.6, height: 1.12),
      headlineMedium: display(22, 700, color: text, spacing: -.4, height: 1.15),
      headlineSmall: display(20, 680, color: text, spacing: -.3, height: 1.2),
      titleLarge: display(17, 660, color: text, spacing: -.2, height: 1.25),
      titleMedium: inter(15, 640, color: text, spacing: -.1, height: 1.3),
      titleSmall: inter(14, 620, color: text, height: 1.3),
      bodyLarge: inter(15, 440, color: text, height: 1.45),
      bodyMedium: inter(14, 440, color: sub, height: 1.45),
      bodySmall: inter(12.5, 440, color: sub, height: 1.4),
      labelLarge: inter(14, 640, color: text, spacing: .1),
      labelMedium: inter(12.5, 620, color: sub, spacing: .3),
      labelSmall: microLabel(sub),
    );

    const controlShape =
        RoundedRectangleBorder(borderRadius: FlowRadii.control);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      extensions: [tones],
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: display(20, 700, color: text, spacing: -.3),
        iconTheme: IconThemeData(color: text),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: tones.card,
        surfaceTintColor: Colors.transparent,
        elevation: dark ? 0 : 1,
        shadowColor: dark ? Colors.transparent : const Color(0x14071C3E),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.card,
          side: BorderSide(color: tones.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          textStyle: inter(15, 680, spacing: .2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          side: BorderSide(color: scheme.outline),
          foregroundColor: text,
          textStyle: inter(15, 640),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: inter(14, 660, spacing: .2),
          shape: controlShape,
          minimumSize: const Size(48, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? FlowColors.navy900 : FlowColors.white,
        hintStyle: inter(15, 420, color: tones.textFaint),
        labelStyle: inter(15, 460, color: sub),
        helperStyle: inter(12.5, 440, color: tones.textFaint),
        errorStyle: inter(12.5, 520, color: tones.danger),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: FlowRadii.control,
          borderSide: BorderSide(color: tones.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FlowRadii.control,
          borderSide: BorderSide(color: tones.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FlowRadii.control,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: FlowRadii.control,
          borderSide: BorderSide(color: tones.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: FlowRadii.control,
          borderSide: BorderSide(color: tones.danger, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? FlowColors.navy900 : FlowColors.white,
        selectedColor: dark ? const Color(0x331DB0FE) : FlowColors.azurePale,
        side: BorderSide(color: tones.line),
        labelStyle: inter(14, 560, color: text),
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.chip),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
      dividerTheme: DividerThemeData(color: tones.line, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? FlowColors.navy900 : FlowColors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: dark ? FlowColors.navy900 : FlowColors.white,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(FlowRadius.sheet)),
        ),
        showDragHandle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? FlowColors.navy850 : FlowColors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.dialog),
        titleTextStyle: display(20, 700, color: text, spacing: -.3),
        contentTextStyle: inter(14, 440, color: sub, height: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? FlowColors.navy800 : FlowColors.ink,
        contentTextStyle: inter(14, 520, color: FlowColors.mist),
        actionTextColor: FlowColors.azure,
        shape: RoundedRectangleBorder(borderRadius: FlowRadii.control),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: sub,
        labelStyle: inter(14, 700, spacing: 1),
        unselectedLabelStyle: inter(14, 600, spacing: 1),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: scheme.primary, width: 3),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? FlowColors.navy950 : FlowColors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? const Color(0x2E1DB0FE) : FlowColors.azurePale,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? (dark ? FlowColors.azure : FlowColors.azureDeep)
                : sub,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => inter(11.5, states.contains(WidgetState.selected) ? 680 : 560,
              color: states.contains(WidgetState.selected)
                  ? (dark ? FlowColors.azure : FlowColors.azureDeep)
                  : sub),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.onPrimary : sub),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.primary : tones.line),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: tones.line,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: sub,
        titleTextStyle: inter(15, 560, color: text),
        subtitleTextStyle: inter(14, 440, color: sub),
        shape: RoundedRectangleBorder(borderRadius: FlowRadii.control),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: inter(12.5, 520, color: scheme.onInverseSurface),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: dark ? FlowColors.navy850 : FlowColors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.dialog),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
