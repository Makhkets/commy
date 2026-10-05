import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often the chosen server is asked whether it still works.
///
/// Its own provider so tests can make it short. Thirty seconds: a dead
/// server is noticed within a minute (two misses in a row), and one tiny
/// request through the tunnel every half minute is lost in the traffic of a
/// phone that is using it.
final failoverIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// Moves the traffic off a server that stopped answering
/// (`AppSettings.failover`; docs/19-commy-cloud.md, §3.1).
///
/// Watched from the root, like the reachability check. Runs only while all of
/// these hold: the switch is on, the tunnel is up, and the user chose a
/// server by hand — the Auto group already keeps traffic on a live one, and
/// a watchdog second-guessing it would only fight it.
///
/// Every [failoverIntervalProvider] the core measures the chosen server
/// through its own outbound — no request leaves around the tunnel, and none
/// to a host the user did not configure: the probe address is the one "Ping"
/// already uses. Two misses in a row and the candidates are measured the same
/// way: up to [FailoverWatchdog.maxCandidates] servers, the chosen server's
/// own subscription first, the quickest by the last ping first. The fastest
/// that answers is selected inside the running core — open connections to
/// other hosts are not dropped — and the user is told. When no candidate
/// answers either, nothing moves: that is the network, not the server.
final failoverWatchdogProvider = Provider<FailoverWatchdog>((ref) {
  final watchdog = FailoverWatchdog(ref);
  ref
    ..onDispose(watchdog.stop)
    ..listen<AsyncValue<TunnelStatus>>(
      coreStatusProvider,
      (_, __) => watchdog.reconsider(),
    )
    ..listen<AsyncValue<AppSettings>>(
      settingsProvider,
      (_, __) => watchdog.reconsider(),
    );
  watchdog.reconsider();
  return watchdog;
});

/// The timer and the count of misses behind [failoverWatchdogProvider].
class FailoverWatchdog {
  /// Creates the watchdog for [_ref].
  FailoverWatchdog(this._ref);

  final Ref _ref;
  Timer? _timer;
  int _misses = 0;
  bool _checking = false;

  /// Misses in a row before the server is called dead.
  static const int threshold = 2;

  /// Most servers measured to find a replacement.
  static const int maxCandidates = 6;

  /// Whether it is running.
  bool get isWatching => _timer != null;

  /// Starts or stops the timer to match the tunnel and the switch.
  void reconsider() {
    final settings = _ref.read(settingsProvider).value;
    final status = _ref.read(coreStatusProvider).value;
    final watch = (settings?.failover ?? false) &&
        !(settings?.autoSelect ?? false) &&
        (status is TunnelConnected || status is TunnelChecking);
    if (watch && _timer == null) {
      _misses = 0;
      _timer = Timer.periodic(
        _ref.read(failoverIntervalProvider),
        (_) => unawaited(check()),
      );
    } else if (!watch) {
      stop();
    }
  }

  /// Stops the timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _misses = 0;
  }

  /// One look at the chosen server, and a switch when it has failed
  /// [threshold] times in a row. Public for tests.
  Future<void> check() async {
    if (_checking) {
      return;
    }
    _checking = true;
    try {
      await _check();
    } finally {
      _checking = false;
    }
  }

  Future<void> _check() async {
    final current = _ref.read(selectedNodeProvider);
    final settings = _ref.read(settingsProvider).value;
    if (current == null || settings == null) {
      return;
    }
    final probe = Uri.tryParse(settings.latencyProbeUrl);
    if (probe == null) {
      return;
    }
    if (await _measure(current, probe) != null) {
      _misses = 0;
      return;
    }
    _misses++;
    if (_misses < threshold) {
      return;
    }
    final logger = _ref.read(appLoggerProvider)
      ..warn(
        'the chosen server missed $threshold checks; looking for another',
        tag: 'failover',
      );
    final candidates = _candidates(current);
    final measured = await Future.wait(<Future<(ProxyNode, Duration?)>>[
      for (final node in candidates)
        _measure(node, probe).then((latency) => (node, latency)),
    ]);
    ProxyNode? best;
    Duration? bestLatency;
    for (final (node, latency) in measured) {
      if (latency != null && (bestLatency == null || latency < bestLatency)) {
        best = node;
        bestLatency = latency;
      }
    }
    _misses = 0;
    if (best == null) {
      logger.info('no other server answered either; staying', tag: 'failover');
      return;
    }
    // Still the same situation after the measuring? The user may have
    // picked a server, switched failover off or disconnected meanwhile.
    final still = _ref.read(settingsProvider).value;
    if (_timer == null ||
        !(still?.failover ?? false) ||
        _ref.read(selectedNodeProvider)?.id != current.id) {
      return;
    }
    final tunnel = _ref.read(tunnelControllerProvider.notifier);
    await tunnel.selectNode(best);
    if (_ref.read(selectedNodeProvider)?.id == best.id) {
      tunnel.reportFailover(best);
      logger.info('switched to another server', tag: 'failover');
    }
  }

  List<ProxyNode> _candidates(ProxyNode current) {
    final all = _ref.read(nodesProvider).value ?? const <ProxyNode>[];
    final others = <ProxyNode>[
      for (final node in all)
        if (node.id != current.id) node,
    ]..sort((a, b) {
        final sameA = a.subscriptionId == current.subscriptionId ? 0 : 1;
        final sameB = b.subscriptionId == current.subscriptionId ? 0 : 1;
        if (sameA != sameB) {
          return sameA - sameB;
        }
        final la = a.latency;
        final lb = b.latency;
        if (la == null || lb == null) {
          return la == null ? (lb == null ? 0 : 1) : -1;
        }
        return la.compareTo(lb);
      });
    return others.take(maxCandidates).toList();
  }

  Future<Duration?> _measure(ProxyNode node, Uri probe) async {
    try {
      return await _ref
          .read(coreClientProvider)
          .urlTest(SingBoxTags.forNode(node), probe);
    } on Object {
      return null;
    }
  }
}
