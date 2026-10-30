/// Intrinsic dimensions of the components: control heights, icon sizes,
/// stroke widths, track sizes.
///
/// These are not part of the 4 pt spacing scale — they are the geometry of a
/// specific control, the kind of number a designer picks once and never
/// changes. They live here so that no widget file has to contain a bare
/// number (rule R4).
abstract final class CommySizes {
  /// Icon inside a line of text — 16.
  static const double iconInline = 16;

  /// Icon inside a button or list row — 20.
  static const double iconControl = 20;

  /// Icon in navigation — 22.
  static const double iconNav = 22;

  /// Icon of an empty state — 32.
  static const double iconEmpty = 32;

  /// Smallest tap target we ship, per the pre-merge checklist — 48.
  static const double minTapTarget = 48;

  /// Height of a standard button — 44.
  static const double buttonHeight = 44;

  /// Height of the one main action of a screen — 52. "Connect" on the main
  /// screen; nothing else is that large.
  static const double buttonHeightLarge = 52;

  /// Height of a compact button, used inside dense rows — 36.
  static const double buttonHeightSmall = 36;

  /// Side of a square icon button. Equal to [minTapTarget] on purpose.
  static const double iconButtonSize = 48;

  /// Height of a single-line text field — 48.
  static const double fieldHeight = 48;

  /// Height of the search field — 44, the iOS search bar's.
  static const double searchHeight = 44;

  /// Height of the segmented control's track — 36. Its segments keep their
  /// taps up to [minTapTarget] through transparent margin.
  static const double segmentedHeight = 36;

  /// Inset of the segmented control's thumb inside its track — 2.
  static const double segmentedInset = 2;

  /// How far a pressed control shrinks — to 97 %. docs/04 §7.1.
  static const double pressScale = 0.97;

  /// Opacity of a control that cannot be used — the switch and the segments
  /// fade as a whole, the way iOS shows it.
  static const double disabledOpacity = 0.4;

  /// Hairline border — 1.
  static const double borderThin = 1;

  /// Emphasised border, and the connect ring in every state but two — 1.5.
  static const double borderMedium = 1.5;

  /// The connect ring when connected or errored, and the ring around a
  /// control that has keyboard focus — 2.
  static const double borderThick = 2;

  /// Switch track width — 51, the iOS switch's.
  static const double switchWidth = 51;

  /// Switch track height — 31.
  static const double switchHeight = 31;

  /// Switch thumb diameter — 27.
  static const double switchThumb = 27;

  /// Width the thumb stretches to while it is pressed — 33, as iOS does it.
  static const double switchThumbPressed = 33;

  /// Inset of the thumb inside the track — 2.
  static const double switchPadding = 2;

  /// Checkbox side — 22.
  static const double checkboxSize = 22;

  /// Radio outer diameter — 22.
  static const double radioSize = 22;

  /// Radio inner dot diameter — 10.
  static const double radioDot = 10;

  /// Status dot inside a pill — 8.
  static const double statusDot = 8;

  /// Country flag width — 26.
  static const double flagWidth = 26;

  /// Country flag height — 20.
  static const double flagHeight = 20;

  /// Width of one latency bar — 2.5.
  static const double latencyBarWidth = 2.5;

  /// Gap between latency bars — 2.
  static const double latencyBarGap = 2;

  /// Height of the tallest latency bar — 12.
  static const double latencyBarHeight = 12;

  /// How many bars a latency badge draws — 3.
  static const int latencyBarCount = 3;

  /// Height of the quota track — 4.
  static const double quotaBarHeight = 4;

  /// Divider thickness — 1.
  static const double dividerThickness = 1;

  /// Default height of a skeleton line — 14.
  static const double skeletonHeight = 14;

  /// Default spinner diameter — 20.
  static const double spinnerSize = 20;

  /// Spinner stroke — 2.
  static const double spinnerStroke = 2;

  /// How much of the spinner circle is drawn, in turns — 0.25.
  static const double spinnerSweep = 0.25;

  /// Height of the traffic sparkline — 48.
  static const double chartHeight = 48;

  /// Stroke of the traffic sparkline — 1.5.
  static const double chartStroke = 1.5;

  /// Edge of the rounded tile a server row draws its flag on — 36.
  ///
  /// The tile, taken from INCY, gives every row the same square to start
  /// from, so a list of flags reads as a column of icons rather than a ragged
  /// edge of coloured stripes.
  static const double flagTile = 36;

  /// Edge of a QR code — 220.
  ///
  /// Sized for the camera, not for the layout: a phone reading a code off
  /// another phone wants modules it can separate, and the longest payload we
  /// will draw (2 000 characters, `QrPayload.maxLength`) is a version-40
  /// symbol of 177 modules. Below roughly this edge those modules fall under
  /// a pixel each on a compact screen.
  static const double qrSize = 220;

  /// The quiet zone drawn around a QR code — 16.
  ///
  /// A decoder needs clear ground on all four sides; without it a code that
  /// reaches the edge of its card scans on some phones and not on others.
  static const double qrQuietZone = 16;

  /// Width of the drag handle at the top of a bottom sheet — 36.
  static const double sheetHandleWidth = 36;

  /// Height of that handle — 5.
  static const double sheetHandleHeight = 5;

  /// Widest a dialog gets on desktop — 480.
  static const double dialogMaxWidth = 480;

  /// Height of the app bar — 56.
  static const double appBarHeight = 56;

  /// Width of the navigation rail on tablet — 88.
  static const double railWidth = 88;

  /// Width of the labelled sidebar on desktop — 260.
  static const double sidebarWidth = 260;

  /// Narrowest the detail pane may become before it is dropped — 360.
  static const double detailPaneMinWidth = 360;

  /// Widest a toast gets — 420.
  static const double toastMaxWidth = 420;

  /// Height of a full-width progress or shimmer band — 8.
  static const double bandHeight = 8;

  /// Width of the column the route's rail is drawn in — 24.
  static const double routeRail = 24;

  /// Diameter of a stop on the route — 12.
  static const double routeDot = 12;

  /// Diameter of the server's stop, the one the route is about — 16.
  static const double routeDotServer = 16;

  /// Diameter of the marker on the stop where the route broke — 20. Large
  /// enough to carry its ✕ at 3:1.
  static const double routeMarker = 20;

  /// Stroke of a leg of the route — 2.
  static const double routeStroke = 2;

  /// Length of a dash of a leg that does not exist yet — 4, with gaps of
  /// [routeDashGap].
  static const double routeDash = 4;

  /// Gap between two dashes — 4.
  static const double routeDashGap = 4;

  /// How much of a leg the travelling highlight covers — 40 %.
  static const double routeSweepFraction = 0.4;

  /// Shortest a leg of the route is drawn — 16, so two stops never touch.
  static const double routeLegMin = 16;

  /// Widest a paragraph runs before it is set in a narrower column — 560.
  /// About 75 characters of body text (docs/04 §3).
  static const double readingWidth = 560;
}
