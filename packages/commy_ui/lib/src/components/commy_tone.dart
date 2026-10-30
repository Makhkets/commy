import 'package:commy_ui/src/tokens/colors.dart';
import 'package:flutter/material.dart';

/// The meaning a small coloured element carries.
///
/// Colour in this product says one thing: state. A tone is how a chip, badge,
/// banner, toast or the route asks for that meaning without naming a colour —
/// and, just as importantly, every widget that takes a tone also renders an
/// icon or a word, because colour never carries a meaning on its own
/// (docs/04-design-system.md §2).
enum CommyTone {
  /// No state. Uses the neutral surface and primary text.
  neutral,

  /// Connected. The signature hue.
  connected,

  /// Transitional: starting or stopping.
  connecting,

  /// Something failed.
  error,

  /// Informational.
  info,

  /// Disconnected.
  idle;

  /// Foreground colour of this tone: text, icon, dot, border.
  Color foreground(CommyColors colors) => switch (this) {
        CommyTone.neutral => colors.textPrimary,
        CommyTone.connected => colors.statusConnected,
        CommyTone.connecting => colors.statusConnecting,
        CommyTone.error => colors.statusError,
        CommyTone.info => colors.statusInfo,
        CommyTone.idle => colors.statusIdle,
      };

  /// This tone as a line, a dot or a fill (3:1 against the canvas).
  Color solid(CommyColors colors) => switch (this) {
        CommyTone.neutral => colors.textPrimary,
        CommyTone.connected => colors.statusConnectedSolid,
        CommyTone.connecting => colors.statusConnectingSolid,
        CommyTone.error => colors.statusErrorSolid,
        CommyTone.info => colors.statusInfoSolid,
        CommyTone.idle => colors.statusIdleSolid,
      };

  /// A glyph drawn on [solid].
  Color onSolid(CommyColors colors) => switch (this) {
        CommyTone.neutral => colors.textInverse,
        CommyTone.connected => colors.statusConnectedOnSolid,
        CommyTone.connecting => colors.statusConnectingOnSolid,
        CommyTone.error => colors.statusErrorOnSolid,
        CommyTone.info => colors.statusInfoOnSolid,
        CommyTone.idle => colors.statusIdleOnSolid,
      };

  /// Backing wash of this tone: the fill behind [foreground].
  Color wash(CommyColors colors) => switch (this) {
        CommyTone.neutral => colors.fill,
        CommyTone.connected => colors.statusConnectedWash,
        CommyTone.connecting => colors.statusConnectingWash,
        CommyTone.error => colors.statusErrorWash,
        CommyTone.info => colors.statusInfoWash,
        CommyTone.idle => colors.statusIdleWash,
      };
}
