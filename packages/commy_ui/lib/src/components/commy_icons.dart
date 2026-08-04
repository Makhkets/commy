import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every icon the design system uses, named once.
///
/// Lucide is the only icon family in the product — mixing families is the
/// first thing that gives away an unconsidered interface. This class exists
/// for a second reason as well: upstream Lucide renames glyphs between
/// releases (`alert-circle` became `circle-alert`, `more-horizontal` became
/// `ellipsis`), so a version bump must break exactly one file, not forty.
///
/// Grid 24, stroke 1.75, rounded caps. Sizes come from `CommySizes`:
/// 16 in a line of text, 20 in buttons and rows, 22 in navigation, 32 in
/// empty states.
abstract final class CommyIcons {
  /// Confirmation mark inside a checkbox.
  static const IconData check = LucideIcons.check;

  /// Dismiss, clear, close.
  static const IconData close = LucideIcons.x;

  /// Add — the plus in the app bar.
  static const IconData add = LucideIcons.plus;

  /// Settings — the cog in the app bar.
  static const IconData settings = LucideIcons.settings;

  /// The power sign. Used outside the connect button only; the button paints
  /// its own so that the 2.2 stroke of the spec can be honoured.
  static const IconData power = LucideIcons.power;

  /// Search.
  static const IconData search = LucideIcons.search;

  /// Refresh, re-check, update.
  static const IconData refresh = LucideIcons.refreshCw;

  /// Upload direction in a traffic readout.
  static const IconData arrowUp = LucideIcons.arrowUp;

  /// Download direction in a traffic readout.
  static const IconData arrowDown = LucideIcons.arrowDown;

  /// Expand a collapsed group.
  static const IconData chevronDown = LucideIcons.chevronDown;

  /// Collapse an expanded group.
  static const IconData chevronUp = LucideIcons.chevronUp;

  /// Open a detail, move forward.
  static const IconData chevronRight = LucideIcons.chevronRight;

  /// Go back.
  static const IconData chevronLeft = LucideIcons.chevronLeft;

  /// Overflow menu.
  static const IconData more = LucideIcons.ellipsis;

  /// Drag handle of a reorderable row.
  static const IconData drag = LucideIcons.gripVertical;

  /// Copy to clipboard.
  static const IconData copy = LucideIcons.copy;

  /// Delete.
  static const IconData delete = LucideIcons.trash2;

  /// Edit, rename.
  static const IconData edit = LucideIcons.pencil;

  /// A link, a subscription URL.
  static const IconData link = LucideIcons.link;

  /// Leave the app for a web page.
  static const IconData externalLink = LucideIcons.externalLink;

  /// Neutral information.
  static const IconData info = LucideIcons.info;

  /// A failure the user has to read.
  static const IconData error = LucideIcons.circleAlert;

  /// A warning that is not yet a failure.
  static const IconData warning = LucideIcons.triangleAlert;

  /// Success.
  static const IconData success = LucideIcons.circleCheck;

  /// Blocked traffic — the `block` routing action.
  static const IconData block = LucideIcons.ban;

  /// Direct traffic — the `direct` routing action.
  static const IconData direct = LucideIcons.arrowRight;

  /// Proxied traffic — the `proxy` routing action.
  static const IconData proxy = LucideIcons.shield;

  /// Disconnected, no route.
  static const IconData offline = LucideIcons.wifiOff;

  /// A globe, used as the neutral country fallback and for "global" routing.
  static const IconData globe = LucideIcons.globe;

  /// Elapsed time, expiry.
  static const IconData clock = LucideIcons.clock;

  /// Logs and the configuration document.
  static const IconData document = LucideIcons.fileText;

  /// An empty list.
  static const IconData empty = LucideIcons.inbox;

  /// A server, a node.
  static const IconData server = LucideIcons.server;

  /// Routing rules.
  static const IconData routing = LucideIcons.gitBranch;

  /// Diagnostics.
  static const IconData diagnostics = LucideIcons.activity;
}
