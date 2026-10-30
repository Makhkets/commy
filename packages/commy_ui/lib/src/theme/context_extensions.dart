import 'package:commy_ui/src/tokens/breakpoints.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/elevation.dart';
import 'package:commy_ui/src/tokens/layout_size.dart';
import 'package:commy_ui/src/tokens/motion.dart';
import 'package:commy_ui/src/tokens/radii.dart';
import 'package:commy_ui/src/tokens/spacing.dart';
import 'package:commy_ui/src/tokens/tag_colors.dart';
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

  /// Shadow sets: only floating surfaces cast one, and only in light.
  CommyElevation get elevation {
    final theme = Theme.of(this);
    return theme.extension<CommyElevation>() ??
        (theme.brightness == Brightness.dark
            ? CommyElevation.dark
            : CommyElevation.light);
  }

  /// Colours of the protocol tags on a server row.
  CommyTagColors get tagColors {
    final theme = Theme.of(this);
    return theme.extension<CommyTagColors>() ??
        (theme.brightness == Brightness.dark
            ? CommyTagColors.dark
            : CommyTagColors.light);
  }

  /// Whether the platform asked for reduced motion.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Which layout the current window width belongs to.
  CommyLayoutSize get layoutSize =>
      CommyBreakpoints.sizeFor(MediaQuery.sizeOf(this).width);

  /// Side inset of a screen (docs/04-design-system.md §4): 16 on a phone,
  /// 24 on a tablet, 32 on a laptop and 40 from 1440 dp up.
  double get screenInset {
    final size = layoutSize;
    if (size.isCompact) {
      return spacing.s4;
    }
    if (size.isMedium) {
      return spacing.s6;
    }
    return MediaQuery.sizeOf(this).width >= CommyBreakpoints.wide
        ? spacing.s10
        : spacing.s8;
  }
}
