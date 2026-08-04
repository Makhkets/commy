import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/traffic_history.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Throughput over the last minute, plus the totals for this session.
///
/// The window is sixty seconds because that is what `CommyThresholds` fixes
/// for the chart and what a person can hold in their head while watching a
/// transfer. Longer history belongs to a daily table, which is not in 1.0.
class StatsScreen extends ConsumerWidget {
  /// Creates the screen.
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final history = ref.watch(trafficHistoryProvider);

    if (history.samples.isEmpty) {
      return DiagnosticsShell(
        route: AppRoutes.diagnosticsStats,
        child: EmptyState(
          icon: CommyIcons.diagnostics,
          title: t.diagnostics.statsEmpty,
          message: t.diagnostics.statsEmptyBody,
        ),
      );
    }

    final latest = history.samples.last;

    return DiagnosticsShell(
      route: AppRoutes.diagnosticsStats,
      child: ListView(
        padding: EdgeInsets.only(bottom: spacing.s10),
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: TrafficChart(
              samples: history.samples,
              semanticLabel: t.diagnostics.statsWindow,
            ),
          ),
          SectionLabel(t.diagnostics.statsWindow),
          SettingsSection(
            children: <Widget>[
              SettingsTile(
                icon: CommyIcons.arrowUp,
                title: t.metrics.up,
                value: CommyByteFormat.rate(latest.uplink),
              ),
              SettingsTile(
                icon: CommyIcons.arrowDown,
                title: t.metrics.down,
                value: CommyByteFormat.rate(latest.downlink),
              ),
            ],
          ),
          SectionLabel(t.diagnostics.statsTotal),
          SettingsSection(
            children: <Widget>[
              SettingsTile(
                icon: CommyIcons.arrowUp,
                title: t.diagnostics.statsUp,
                value: CommyByteFormat.bytes(latest.uplinkTotal),
              ),
              SettingsTile(
                icon: CommyIcons.arrowDown,
                title: t.diagnostics.statsDown,
                value: CommyByteFormat.bytes(latest.downlinkTotal),
              ),
            ],
          ),
          SizedBox(height: spacing.s6),
        ],
      ),
    );
  }
}
