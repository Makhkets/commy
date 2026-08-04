import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The frame the four diagnostics tabs share.
///
/// The tabs are routes rather than a `TabBarView` so that an error banner
/// anywhere in the app can send the user to exactly one of them — "открыть
/// логи" has to land on the logs, not on whichever tab happened to be last.
class DiagnosticsShell extends StatelessWidget {
  /// Creates the frame.
  const DiagnosticsShell({
    required this.route,
    required this.child,
    this.actions = const <Widget>[],
    super.key,
  });

  /// Which tab is showing.
  final String route;

  /// The tab body.
  final Widget child;

  /// Controls for the app bar, at most two.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;

    return AdaptiveScaffold(
      appBar: CommyAppBar.section(
        title: t.diagnostics.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.settings),
        actions: actions,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(spacing.s4),
            child: SegmentedControl<String>(
              value: route,
              segments: <SegmentedControlItem<String>>[
                SegmentedControlItem<String>(
                  value: AppRoutes.diagnosticsLogs,
                  label: t.diagnostics.logs,
                ),
                SegmentedControlItem<String>(
                  value: AppRoutes.diagnosticsConnections,
                  label: t.diagnostics.connections,
                ),
                SegmentedControlItem<String>(
                  value: AppRoutes.diagnosticsConfig,
                  label: t.diagnostics.config,
                ),
                SegmentedControlItem<String>(
                  value: AppRoutes.diagnosticsStats,
                  label: t.diagnostics.stats,
                ),
              ],
              onChanged: (next) {
                if (next != route) {
                  context.go(next);
                }
              },
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
