import 'package:flutter/material.dart';

/// The two colours a QR code is drawn with.
///
/// Not theme colours, and deliberately not derived from them. A scanner reads
/// a QR by contrast between the modules and the quiet zone, and it expects
/// dark modules on a light ground; a code painted in the dark theme's surface
/// and text colours is a code a camera across a table gives up on — and it
/// fails silently, which is the worst way for a share button to fail.
///
/// So a QR looks the same in both themes, and the card behind it carries its
/// own light ground rather than the screen's. They live in `tokens/` because
/// that is where rule R4 allows a colour literal to exist, next to
/// `CommyFlagPalette`, which is here for the same kind of reason.
abstract final class CommyQrPalette {
  /// The quiet zone and the light modules.
  static const Color ground = Color(0xFFFFFFFF);

  /// The dark modules.
  ///
  /// Pure black rather than the theme's text colour: the contrast ratio is
  /// what a decoder measures, and there is no reason to spend any of it.
  static const Color module = Color(0xFF000000);
}
