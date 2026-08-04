import 'package:commy_ui/src/tokens/colors.dart';
import 'package:flutter/material.dart';

/// The meaning a small coloured element carries.
///
/// Colour in this product says exactly one thing: connection state. A tone is
/// how a chip, badge, pill, banner or toast asks for that meaning without
/// naming a colour — and, just as importantly, every widget that takes a tone
/// also renders an icon or a word, because colour never carries a meaning on
/// its own (docs/04-design-system.md, "Контраст").
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

  /// Backing wash of this tone: the fill behind [foreground].
  Color wash(CommyColors colors) => switch (this) {
        CommyTone.neutral => colors.bgOverlay,
        CommyTone.connected => colors.statusConnectedWash,
        CommyTone.connecting => colors.statusConnectingWash,
        CommyTone.error => colors.statusErrorWash,
        CommyTone.info => colors.statusInfoWash,
        CommyTone.idle => colors.statusIdleWash,
      };
}
