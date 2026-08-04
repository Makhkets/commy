import 'package:commy_ui/src/tokens/breakpoints.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/connect_tokens.dart';
import 'package:commy_ui/src/tokens/elevation.dart';
import 'package:commy_ui/src/tokens/layout_size.dart';
import 'package:commy_ui/src/tokens/motion.dart';
import 'package:commy_ui/src/tokens/radii.dart';
import 'package:commy_ui/src/tokens/spacing.dart';
import 'package:commy_ui/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// Short reads for the design tokens hanging off the current theme.
///
/// This is the entire public way to get at a token:
///
/// ```dart
/// Container(color: context.colors.bgSurface);
/// ```
///
/// Each getter falls back to the shipped token set when the theme has no
/// extension — a widget dropped into a bare `MaterialApp` still renders,
/// which keeps widget tests from needing ceremony.
extension CommyThemeContext on BuildContext {
  /// Semantic colours of the active theme.
  CommyColors get colors {
    final theme = Theme.of(this);
    return theme.extension<CommyColors>() ??
        (theme.brightness == Brightness.dark
            ? CommyColors.dark
            : CommyColors.light);
  }

  /// The 4 pt spacing scale.
  CommySpacing get spacing =>
      Theme.of(this).extension<CommySpacing>() ?? CommySpacing.standard;

  /// The corner radius scale.
  CommyRadii get radii =>
      Theme.of(this).extension<CommyRadii>() ?? CommyRadii.standard;

  /// The type scale.
  CommyTypography get typography =>
      Theme.of(this).extension<CommyTypography>() ?? CommyTypography.standard;

  /// Durations and curves.
  ///
  /// Returns [CommyMotion.none] — every duration zero — when the platform
  /// asks for reduced motion. Widgets that animate through implicit widgets
  /// therefore honour the setting for free; the few that drive an
  /// [AnimationController] check [reduceMotion] as well.
  CommyMotion get motion {
    if (reduceMotion) {
      return CommyMotion.none;
    }
    return Theme.of(this).extension<CommyMotion>() ?? CommyMotion.standard;
  }

  /// Elevation shadow sets. Empty on the dark theme by design.
  CommyElevation get elevation {
    final theme = Theme.of(this);
    return theme.extension<CommyElevation>() ??
        (theme.brightness == Brightness.dark
            ? CommyElevation.dark
            : CommyElevation.light);
  }

  /// Geometry and derived colours of the connect button.
  CommyConnectTokens get connectTokens {
    final theme = Theme.of(this);
    return theme.extension<CommyConnectTokens>() ??
        (theme.brightness == Brightness.dark
            ? CommyConnectTokens.dark
            : CommyConnectTokens.light);
  }

  /// Whether the platform asked for reduced motion.
  bool get reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Which layout the current window width belongs to.
  CommyLayoutSize get layoutSize =>
      CommyBreakpoints.sizeFor(MediaQuery.sizeOf(this).width);

  /// Base screen inset: `space/4` on mobile, `space/6` from tablet up.
  double get screenInset =>
      layoutSize.isCompact ? spacing.s4 : spacing.s6;
}
