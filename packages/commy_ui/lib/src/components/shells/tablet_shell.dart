import 'package:commy_ui/src/components/atoms/commy_icon_button.dart';
import 'package:commy_ui/src/components/shells/commy_destination.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The layout between the two breakpoints: a rail and, when it fits, a detail
/// pane.
///
/// Sections come back into permanent navigation here because there is finally
/// room for them — the rail costs 88 dp of a window at least 600 wide, whereas
/// on a phone the same idea costs a quarter of the screen's height. The rail
/// is icons only; each one carries its name as a tooltip and as its accessible
/// label, so nothing is left to be guessed from a glyph.
///
/// [detail] is dropped rather than squeezed when the window cannot hold two
/// panes of [CommySizes.detailPaneMinWidth]. A 200 dp master list next to a
/// 360 dp detail is worse than one pane and a push, and the screen is expected
/// to push the detail as its own route in that case.
class TabletShell extends StatelessWidget {
  /// Creates the tablet shell.
  const TabletShell({
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.appBar,
    this.detail,
    super.key,
  }) : assert(
          selectedIndex >= 0,
          'The rail always has one destination selected.',
        );

  /// Master content, to the right of the rail.
  final Widget body;

  /// Entries of the rail. An empty list hides the rail entirely, which is what
  /// a modal-ish screen wants.
  final List<CommyDestination> destinations;

  /// Index of the selected destination.
  final int selectedIndex;

  /// Called with the index of the destination that was tapped.
  final ValueChanged<int> onDestinationSelected;

  /// Top bar over the master pane, normally a `CommyAppBar`.
  final PreferredSizeWidget? appBar;

  /// Detail pane on the trailing side, or `null` when nothing is open.
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bar = appBar;

    return Scaffold(
      backgroundColor: colors.bgCanvas,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (destinations.isNotEmpty) ...<Widget>[
              _Rail(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
              ),
              _Seam(color: colors.borderSubtle),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final master = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (bar != null) bar,
                      Expanded(child: body),
                    ],
                  );

                  final pane = detail;
                  final fits =
                      constraints.maxWidth >= CommySizes.detailPaneMinWidth * 2;
                  if (pane == null || !fits) {
                    return master;
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: master),
                      _Seam(color: colors.borderSubtle),
                      SizedBox(
                        width: CommySizes.detailPaneMinWidth,
                        child: pane,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vertical hairline between two panes.
class _Seam extends StatelessWidget {
  const _Seam({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CommySizes.dividerThickness,
      child: ColoredBox(color: color, child: const SizedBox.expand()),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<CommyDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return SizedBox(
      width: CommySizes.railWidth,
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            SizedBox(height: spacing.s4),
            for (var index = 0; index < destinations.length; index++)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.s2),
                child: CommyIconButton(
                  icon: destinations[index].iconFor(
                    isSelected: index == selectedIndex,
                  ),
                  onPressed: () => onDestinationSelected(index),
                  semanticLabel: destinations[index].label,
                  tooltip: destinations[index].label,
                  isSelected: index == selectedIndex,
                  size: CommySizes.iconNav,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
