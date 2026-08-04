import 'package:commy_ui/src/components/shells/commy_destination.dart';
import 'package:commy_ui/src/components/shells/desktop_shell.dart';
import 'package:commy_ui/src/components/shells/mobile_shell.dart';
import 'package:commy_ui/src/components/shells/tablet_shell.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/layout_size.dart';
import 'package:flutter/material.dart';

/// Picks the shell that belongs to the current window width.
///
/// This is the only widget in the package that reads the width and decides
/// something because of it. Screens hand it the same four things every time —
/// a bar, a body, the sections, and an optional detail — and never learn which
/// of the three layouts they ended up in. That is the whole point: the moment
/// a screen asks "am I on a tablet?", the three layouts start diverging in
/// ways nobody planned.
///
/// The breakpoints are `CommyBreakpoints`, read through
/// [CommyThemeContext.layoutSize]: 600 and 1000 dp.
///
/// | Width | Shell | Navigation |
/// |---|---|---|
/// | < 600 | `MobileShell` | none — the app bar is the way out |
/// | 600–1000 | `TabletShell` | icon rail, detail pane when it fits |
/// | > 1000 | `DesktopShell` | labelled sidebar, two panes, dialogs |
class AdaptiveScaffold extends StatelessWidget {
  /// Creates an adaptive scaffold.
  const AdaptiveScaffold({
    required this.body,
    this.appBar,
    this.destinations = const <CommyDestination>[],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.detail,
    this.floatingAction,
    this.sidebarHeader,
    super.key,
  });

  /// The screen's content.
  final Widget body;

  /// Top bar, normally a `CommyAppBar`.
  final PreferredSizeWidget? appBar;

  /// Sections shown in the rail or the sidebar.
  ///
  /// Empty on mobile-first screens and on anything modal — an empty list is
  /// the ordinary case, not a degenerate one, because below 600 dp there is
  /// no persistent navigation at all.
  final List<CommyDestination> destinations;

  /// Index of the selected section.
  final int selectedIndex;

  /// Called with the index of the section that was chosen. Required whenever
  /// [destinations] is not empty.
  final ValueChanged<int>? onDestinationSelected;

  /// Detail pane, shown beside [body] from the second breakpoint up and only
  /// when two panes actually fit.
  final Widget? detail;

  /// A single floating action, honoured on mobile only.
  final Widget? floatingAction;

  /// Block above the sidebar's destinations, honoured on desktop only.
  final Widget? sidebarHeader;

  @override
  Widget build(BuildContext context) {
    // Not a constructor assert: `destinations.isEmpty` is not a potentially
    // constant expression, and this constructor is const.
    assert(
      destinations.isEmpty || onDestinationSelected != null,
      'Destinations that cannot be selected are decoration.',
    );

    switch (context.layoutSize) {
      case CommyLayoutSize.compact:
        return MobileShell(
          appBar: appBar,
          floatingAction: floatingAction,
          body: body,
        );
      case CommyLayoutSize.medium:
        return TabletShell(
          appBar: appBar,
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected ?? _ignore,
          detail: detail,
          body: body,
        );
      case CommyLayoutSize.expanded:
        return DesktopShell(
          appBar: appBar,
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected ?? _ignore,
          detail: detail,
          sidebarHeader: sidebarHeader,
          body: body,
        );
    }
  }

  /// Stand-in for a screen with no destinations, where nothing can be chosen.
  /// The constructor asserts that this is never reachable with a rail on
  /// screen.
  static void _ignore(int index) {}
}
