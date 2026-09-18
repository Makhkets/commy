import 'package:flutter/widgets.dart';

/// Every icon the design system uses, named once.
///
/// Lucide is the only icon family in the product — mixing families is the
/// first thing that gives away an unconsidered interface. This class exists
/// for a second reason as well: upstream Lucide renames glyphs between
/// releases (`alert-circle` became `circle-alert`, `more-horizontal` became
/// `ellipsis`), so a version bump must break exactly one file, not forty.
///
/// The font is vendored — `fonts/Lucide.ttf`, from `lucide_icons_flutter`
/// 3.1.19 — rather than depended on, and the glyphs are named here by code
/// point. Two reasons, both learned the hard way. The package declares seven
/// font families, one per stroke weight, and Flutter bundles every font a
/// dependency declares whether or not anything draws with it: six unused
/// weights, 2.6 MB, rode along in every APK (rule R11). And with the package
/// resolved separately per workspace member, the goldens were rendered with
/// one version of the glyphs while the app shipped another — a tick that
/// moved between releases already broke them once. A file in the repository
/// cannot drift. Flutter still subsets it at build time, so the app carries
/// only the glyphs below — about 11 KB.
///
/// Every constant is a plain `IconData`, spelled out, and not a subclass or a
/// helper: Flutter's icon tree shaker follows constant instances of `IconData`
/// itself and nothing else, so a glyph built any other way is subset out of
/// the font and draws as tofu — in release builds only.
///
/// To add an icon: take its code point from the `lucide.ttf` of the same
/// release (the package's `lucide_icons.dart` lists them), add a constant, and
/// name the upstream glyph in the trailing comment so the next person can
/// find it.
///
/// Grid 24, stroke 1.75, rounded caps. Sizes come from `CommySizes`:
/// 16 in a line of text, 20 in buttons and rows, 22 in navigation, 32 in
/// empty states.
abstract final class CommyIcons {
  /// Family of the vendored font, as `pubspec.yaml` declares it.
  static const String _family = 'Lucide';

  /// The package the font ships in — this one.
  static const String _package = 'commy_ui';

  /// Confirmation mark inside a checkbox.
  static const IconData check =
      IconData(0xe06c, fontFamily: _family, fontPackage: _package); // check

  /// Dismiss, clear, close.
  static const IconData close =
      IconData(0xe1b2, fontFamily: _family, fontPackage: _package); // x

  /// Add — the plus in the app bar.
  static const IconData add =
      IconData(0xe13d, fontFamily: _family, fontPackage: _package); // plus

  /// Settings — the cog in the app bar.
  static const IconData settings =
      IconData(0xe154, fontFamily: _family, fontPackage: _package); // settings

  /// The power sign. Used outside the connect button only; the button paints
  /// its own so that the 2.2 stroke of the spec can be honoured.
  static const IconData power =
      IconData(0xe140, fontFamily: _family, fontPackage: _package); // power

  /// Search.
  static const IconData search =
      IconData(0xe151, fontFamily: _family, fontPackage: _package); // search

  /// Refresh, re-check, update.
  static const IconData refresh =
      IconData(0xe145, fontFamily: _family, fontPackage: _package); // refreshCw

  /// Upload direction in a traffic readout.
  static const IconData arrowUp =
      IconData(0xe04a, fontFamily: _family, fontPackage: _package); // arrowUp

  /// Download direction in a traffic readout.
  static const IconData arrowDown =
      IconData(0xe042, fontFamily: _family, fontPackage: _package); // arrowDown

  /// Expand a collapsed group.
  static const IconData chevronDown = IconData(
    0xe06d,
    fontFamily: _family,
    fontPackage: _package,
  ); // chevronDown

  /// Collapse an expanded group.
  static const IconData chevronUp =
      IconData(0xe070, fontFamily: _family, fontPackage: _package); // chevronUp

  /// Open a detail, move forward.
  static const IconData chevronRight = IconData(
    0xe06f,
    fontFamily: _family,
    fontPackage: _package,
  ); // chevronRight

  /// Go back.
  static const IconData chevronLeft = IconData(
    0xe06e,
    fontFamily: _family,
    fontPackage: _package,
  ); // chevronLeft

  /// Overflow menu.
  static const IconData more =
      IconData(0xe0b6, fontFamily: _family, fontPackage: _package); // ellipsis

  /// Drag handle of a reorderable row.
  static const IconData drag = IconData(
    0xe0eb,
    fontFamily: _family,
    fontPackage: _package,
  ); // gripVertical

  /// Copy to clipboard.
  static const IconData copy =
      IconData(0xe09e, fontFamily: _family, fontPackage: _package); // copy

  /// Delete.
  static const IconData delete =
      IconData(0xe18e, fontFamily: _family, fontPackage: _package); // trash2

  /// Edit, rename.
  static const IconData edit =
      IconData(0xe1f9, fontFamily: _family, fontPackage: _package); // pencil

  /// A link, a subscription URL.
  static const IconData link =
      IconData(0xe102, fontFamily: _family, fontPackage: _package); // link

  /// Leave the app for a web page.
  static const IconData externalLink = IconData(
    0xe0b9,
    fontFamily: _family,
    fontPackage: _package,
  ); // externalLink

  /// Neutral information.
  static const IconData info =
      IconData(0xe0f9, fontFamily: _family, fontPackage: _package); // info

  /// A failure the user has to read.
  static const IconData error = IconData(
    0xe077,
    fontFamily: _family,
    fontPackage: _package,
  ); // circleAlert

  /// A warning that is not yet a failure.
  static const IconData warning = IconData(
    0xe193,
    fontFamily: _family,
    fontPackage: _package,
  ); // triangleAlert

  /// Success.
  static const IconData success = IconData(
    0xe226,
    fontFamily: _family,
    fontPackage: _package,
  ); // circleCheck

  /// Blocked traffic — the `block` routing action.
  static const IconData block =
      IconData(0xe051, fontFamily: _family, fontPackage: _package); // ban

  /// Direct traffic — the `direct` routing action.
  static const IconData direct = IconData(
    0xe049,
    fontFamily: _family,
    fontPackage: _package,
  ); // arrowRight

  /// Proxied traffic — the `proxy` routing action.
  static const IconData proxy =
      IconData(0xe158, fontFamily: _family, fontPackage: _package); // shield

  /// Disconnected, no route.
  static const IconData offline =
      IconData(0xe1af, fontFamily: _family, fontPackage: _package); // wifiOff

  /// A globe, used as the neutral country fallback and for "global" routing.
  static const IconData globe =
      IconData(0xe0e8, fontFamily: _family, fontPackage: _package); // globe

  /// Elapsed time, expiry.
  static const IconData clock =
      IconData(0xe087, fontFamily: _family, fontPackage: _package); // clock

  /// Logs and the configuration document.
  static const IconData document =
      IconData(0xe0cc, fontFamily: _family, fontPackage: _package); // fileText

  /// An empty list.
  static const IconData empty =
      IconData(0xe0f7, fontFamily: _family, fontPackage: _package); // inbox

  /// A server, a node.
  static const IconData server =
      IconData(0xe153, fontFamily: _family, fontPackage: _package); // server

  /// Routing rules.
  static const IconData routing =
      IconData(0xe0e2, fontFamily: _family, fontPackage: _package); // gitBranch

  /// Diagnostics.
  static const IconData diagnostics =
      IconData(0xe038, fontFamily: _family, fontPackage: _package); // activity
}
