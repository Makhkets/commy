import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:flutter/material.dart';

/// The layout below the first breakpoint: one bar, one column, nothing else.
///
/// **There is no bottom navigation bar, and adding one is a regression.**
/// docs/04-design-system.md, "Навигация: нижнего меню нет", and
/// docs/05-ux-flows.md, "Карта приложения", both spell out why: on mobile
/// Commy has exactly one root screen. Subscriptions, their nodes and
/// hand-added groups live directly under the connect button — on the same
/// screen where the decision to press it is made. A "Servers" tab would
/// duplicate the root screen, and routing and diagnostics are opened less than
/// once a week; giving them a quarter of the bottom bar is a bad trade. The
/// height that buys goes into the list, which is where the user actually
/// spends time.
///
/// The two ways out of the root screen live in the app bar: the cog on the
/// left opens settings, the plus on the right opens import as a sheet.
class MobileShell extends StatelessWidget {
  /// Creates the mobile shell.
  const MobileShell({
    required this.body,
    this.appBar,
    this.floatingAction,
    super.key,
  });

  /// The one column of content.
  final Widget body;

  /// Top bar, normally a `CommyAppBar`.
  final PreferredSizeWidget? appBar;

  /// A single floating action, for the rare screen that needs one. Not a
  /// navigation bar in disguise: one control, no labels, no second slot.
  final Widget? floatingAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgCanvas,
      appBar: appBar,
      body: SafeArea(top: appBar == null, child: body),
      floatingActionButton: floatingAction,
    );
  }
}
