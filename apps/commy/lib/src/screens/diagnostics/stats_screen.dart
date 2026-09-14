import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/traffic_history.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Throughput over the last minute, the totals for this session, and the
/// last week as two numbers a day.
///
/// The window is sixty seconds because that is what `CommyThresholds` fixes
/// for the chart and what a person can hold in their head while watching a
/// transfer. Anything longer is a day at a time and nothing finer: a table of
/// connections would be a browsing history (docs/09-security-privacy.md).
class StatsScreen extends ConsumerWidget {
  /// Creates the screen.
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final history = ref.watch(trafficHistoryProvider);
    final days = ref.watch(trafficDaysProvider).value ?? const <TrafficDay>[];

    if (history.samples.isEmpty && days.isEmpty) {
      return DiagnosticsShell(
        route: AppRoutes.diagnosticsStats,
        child: EmptyState(
          icon: CommyIcons.diagnostics,
          title: t.diagnostics.statsEmpty,
          message: t.diagnostics.statsEmptyBody,
          actionLabel: t.diagnostics.goConnect,
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    // Null with the tunnel down: the week is still worth a screen, the
    // chart of a minute nothing happened in is not.
    final latest = history.samples.isEmpty ? null : history.samples.last;

    return DiagnosticsShell(
      route: AppRoutes.diagnosticsStats,
      child: ListView(
        padding: EdgeInsets.only(bottom: spacing.s10),
        children: <Widget>[
          if (latest != null) ...<Widget>[
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
          ],
          if (days.isNotEmpty) ...<Widget>[
            SectionLabel(t.diagnostics.statsDays),
            SettingsSection(
              children: <Widget>[
                // Newest first: today is what the user came to check.
                for (final day in days.reversed) _DayTile(day: day),
              ],
            ),
          ],
          SizedBox(height: spacing.s6),
        ],
      ),
    );
  }
}

/// One day of the week: the date, the total, and the split underneath.
class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});

  final TrafficDay day;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return SettingsTile(
      title: MaterialLocalizations.of(context).formatMediumDate(day.day),
      subtitle: t.diagnostics.statsDayDetail(
        up: CommyByteFormat.bytes(day.upBytes),
        down: CommyByteFormat.bytes(day.downBytes),
      ),
      value: CommyByteFormat.bytes(day.totalBytes),
    );
  }
}
