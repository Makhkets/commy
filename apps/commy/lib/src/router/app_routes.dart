/// Every path in the app, in one place.
///
/// There is exactly **one** root screen. On a phone the sections are not
/// destinations in a bar; they are places you go from the header and come back
/// from (docs/05-ux-flows.md: "На мобайле нижнего меню нет"). The nesting
/// below is the back-stack, not a tab layout.
abstract final class AppRoutes {
  /// The one root screen: connect button, servers, subscriptions.
  static const String home = '/';

  /// Behind the gear.
  static const String settings = '/settings';

  /// Mode, rules, apps, DNS.
  static const String routing = '/settings/routing';

  /// The diagnostics hub. Redirects to the log tab.
  static const String diagnostics = '/settings/diagnostics';

  /// Theme and language.
  static const String appearance = '/settings/appearance';

  /// Version, core, licences.
  static const String about = '/settings/about';

  /// Core log, monospace, coloured by level.
  static const String diagnosticsLogs = '/diagnostics/logs';

  /// Which rule matched which host.
  static const String diagnosticsConnections = '/diagnostics/connections';

  /// The generated configuration, read only, redacted.
  static const String diagnosticsConfig = '/diagnostics/config';

  /// Throughput over the last minute and the session totals.
  static const String diagnosticsStats = '/diagnostics/stats';

  /// The four diagnostics tabs, in the order the segmented control shows them.
  static const List<String> diagnosticsTabs = <String>[
    diagnosticsLogs,
    diagnosticsConnections,
    diagnosticsConfig,
    diagnosticsStats,
  ];
}
