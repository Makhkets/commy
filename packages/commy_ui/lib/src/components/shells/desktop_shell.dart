import 'package:commy_ui/src/components/shells/commy_destination.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The layout above the second breakpoint: a labelled sidebar and two panes.
///
/// The difference from `TabletShell` is not the width of the navigation but
/// its honesty — at 260 dp every section can say its own name instead of
/// relying on a glyph plus a tooltip. Modals stop being sheets here and become
/// dialogs; `CommySheet` already knows that and callers do not have to.
///
/// Copying the mobile structure onto a desktop window is a mistake, and so is
/// the reverse. docs/05-ux-flows.md is explicit about it, which is why the
/// three shells are three widgets rather than one widget with flags.
class DesktopShell extends StatelessWidget {
  /// Creates the desktop shell.
  const DesktopShell({
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.appBar,
    this.detail,
    this.sidebarHeader,
    super.key,
  }) : assert(
          selectedIndex >= 0,
          'The sidebar always has one destination selected.',
        );

  /// Master content, to the right of the sidebar.
  final Widget body;

  /// Entries of the sidebar. An empty list hides the sidebar entirely.
  final List<CommyDestination> destinations;

  /// Index of the selected destination.
  final int selectedIndex;

  /// Called with the index of the destination that was clicked.
  final ValueChanged<int> onDestinationSelected;

  /// Top bar over the master pane, normally a `CommyAppBar`.
  final PreferredSizeWidget? appBar;

  /// Detail pane on the trailing side, or `null` when nothing is open.
  final Widget? detail;

  /// Optional block above the destinations — the wordmark, a profile, a
  /// connection summary. Already built by the caller.
  final Widget? sidebarHeader;

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
              _Sidebar(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                header: sidebarHeader,
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.header,
  });

  final List<CommyDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final block = header;

    return SizedBox(
      width: CommySizes.sidebarWidth,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.s3,
          vertical: spacing.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (block != null) ...<Widget>[
              block,
              SizedBox(height: spacing.s4),
            ],
            for (var index = 0; index < destinations.length; index++)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.s1),
                child: _SidebarItem(
                  destination: destinations[index],
                  isSelected: index == selectedIndex,
                  onPressed: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.isSelected,
    required this.onPressed,
  });

  final CommyDestination destination;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final foreground = isSelected ? colors.textPrimary : colors.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? colors.accentWash : CommyColors.transparent,
        borderRadius: radii.smAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radii.smAll,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: CommySizes.minTapTarget,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    destination.iconFor(isSelected: isSelected),
                    size: CommySizes.iconNav,
                    color: foreground,
                  ),
                  SizedBox(width: spacing.s3),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.bodyStrong.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
