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

  /// Height of a compact button, used inside dense rows — 36.
  static const double buttonHeightSmall = 36;

  /// Side of a square icon button. Equal to [minTapTarget] on purpose.
  static const double iconButtonSize = 48;

  /// Height of a single-line text field — 48.
  static const double fieldHeight = 48;

  /// Hairline border — 1.
  static const double borderThin = 1;

  /// Emphasised border, and the connect ring in every state but two — 1.5.
  static const double borderMedium = 1.5;

  /// The connect ring when connected or errored — 2.
  static const double borderThick = 2;

  /// Switch track width — 44.
  static const double switchWidth = 44;

  /// Switch track height — 26.
  static const double switchHeight = 26;

  /// Switch thumb diameter — 20.
  static const double switchThumb = 20;

  /// Inset of the thumb inside the track — 3.
  static const double switchPadding = 3;

  /// Checkbox side — 20.
  static const double checkboxSize = 20;

  /// Radio outer diameter — 20.
  static const double radioSize = 20;

  /// Radio inner dot diameter — 8.
  static const double radioDot = 8;

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

  /// Height of the quota track — 6.
  static const double quotaBarHeight = 6;

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

  /// Width of the bar marking the active node on the left of its row — 3.
  static const double activeMarkerWidth = 3;

  /// Height of that bar — 24.
  static const double activeMarkerHeight = 24;

  /// Width of the drag handle at the top of a bottom sheet — 36.
  static const double sheetHandleWidth = 36;

  /// Height of that handle — 4.
  static const double sheetHandleHeight = 4;

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
}
