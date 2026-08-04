import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/connect_tokens.dart';
import 'package:commy_ui/src/tokens/elevation.dart';
import 'package:commy_ui/src/tokens/fonts.dart';
import 'package:commy_ui/src/tokens/motion.dart';
import 'package:commy_ui/src/tokens/radii.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/tokens/spacing.dart';
import 'package:commy_ui/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// Builds the two [ThemeData] objects of the application.
///
/// Everything a widget needs is hung off the theme as a [ThemeExtension] and
/// read back through `context.colors`, `context.spacing` and friends. The
/// Material properties below exist only so that the framework's own widgets —
/// text fields, scrollbars, ink — do not look foreign next to ours.
///
/// Neither theme is "the default". Dark is the one the product was designed
/// in; light is a full derivation, not an afterthought.
abstract final class CommyTheme {
  /// The dark theme.
  static ThemeData get dark => _build(
        colors: CommyColors.dark,
        elevation: CommyElevation.dark,
        connect: CommyConnectTokens.dark,
        brightness: Brightness.dark,
      );

  /// The light theme.
  static ThemeData get light => _build(
        colors: CommyColors.light,
        elevation: CommyElevation.light,
        connect: CommyConnectTokens.light,
        brightness: Brightness.light,
      );

  /// Maps the type scale onto Material's [TextTheme].
  ///
  /// Our own widgets never read this — they take styles from
  /// `context.typography`. It exists so that a stray framework widget picks up
  /// Inter and the right colour instead of Roboto and black.
  static TextTheme textThemeOf(
    CommyTypography type,
    CommyColors colors,
  ) {
    return TextTheme(
      displayLarge: type.displayXl,
      displayMedium: type.display,
      displaySmall: type.title1,
      headlineLarge: type.title1,
      headlineMedium: type.title2,
      headlineSmall: type.title3,
      titleLarge: type.title2,
      titleMedium: type.title3,
      titleSmall: type.bodyStrong,
      bodyLarge: type.bodyLarge,
      bodyMedium: type.body,
      bodySmall: type.caption,
      labelLarge: type.bodyStrong,
      labelMedium: type.captionStrong,
      labelSmall: type.label,
    ).apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );
  }

  static ThemeData _build({
    required CommyColors colors,
    required CommyElevation elevation,
    required CommyConnectTokens connect,
    required Brightness brightness,
  }) {
    const type = CommyTypography.standard;
    const radii = CommyRadii.standard;
    final textTheme = textThemeOf(type, colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: CommyFonts.uiQualified,
      scaffoldBackgroundColor: colors.bgCanvas,
      canvasColor: colors.bgCanvas,
      splashColor: colors.accentWash,
      highlightColor: colors.accentWash,
      hoverColor: colors.accentWash,
      dividerColor: colors.borderSubtle,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accentSolid,
        onPrimary: colors.accentOnSolid,
        secondary: colors.statusConnected,
        onSecondary: colors.textInverse,
        error: colors.statusError,
        onError: colors.textInverse,
        surface: colors.bgSurface,
        onSurface: colors.textPrimary,
        outline: colors.borderDefault,
        outlineVariant: colors.borderSubtle,
        scrim: colors.bgScrim,
        surfaceTint: CommyColors.transparent,
      ),
      iconTheme: IconThemeData(
        color: colors.textSecondary,
        size: CommySizes.iconControl,
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: CommySizes.dividerThickness,
        space: CommySizes.dividerThickness,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accentSolid,
        selectionColor: colors.accentWash,
        selectionHandleColor: colors.accentSolid,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.bgRaised,
          borderRadius: radii.xsAll,
          border: Border.all(color: colors.borderDefault),
        ),
        textStyle: type.caption.copyWith(color: colors.textPrimary),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(colors.borderStrong),
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        elevation,
        connect,
        type,
        radii,
        CommySpacing.standard,
        CommyMotion.standard,
      ],
    );
  }
}
