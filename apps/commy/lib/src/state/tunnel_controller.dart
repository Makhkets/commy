import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The connect flow: status in, actions out.
///
/// The status the button draws is **not** simply the core's status. Two things
/// the core cannot know are folded in here:
///
/// * a call that failed before the core was ever reached — a config that would
///   not build, a node that vanished — has to look like an error, not like
///   nothing happening;
/// * the gap between tapping connect and the core's first `starting` event has
///   to look busy, or the button reads as dead for a few hundred milliseconds.
///
/// Everything else is the core's word and is passed through untouched.
library;

/// The tag the log lines from this file carry.
const String _tag = 'tunnel';

/// Live status straight from the core.
final coreStatusProvider = StreamProvider<TunnelStatus>((ref) {
  return ref.watch(coreClientProvider).status;
});

/// Live throughput. One sample a second while the tunnel is up.
final trafficProvider = StreamProvider<TrafficSample>((ref) {
  return ref.watch(coreClientProvider).traffic;
});

/// Open connections, refreshed by the core.
final connectionsProvider = StreamProvider<List<ConnectionInfo>>((ref) {
  return ref.watch(coreClientProvider).connections;
});

/// Everything the log screen shows: core lines and our own, merged.
final logLinesProvider = StreamProvider<List<LogLine>>((ref) {
  return ref.watch(logRepositoryProvider).watch();
});

/// A second-resolution clock for the session timer and connection ages.
///
/// One ticker for the whole app: a `Timer.periodic` per row is how a list of
/// forty connections turns into forty rebuilds a second.
final clockProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});

/// Pipes the core's log stream and our own logger into the log repository.
///
/// Watched once, from the root widget, so the buffer keeps filling while the
/// user is on any screen — a log that only records while the log screen is
/// open answers no question anybody has.
final logPumpProvider = Provider<void>((ref) {
  final core = ref.watch(coreClientProvider);
  final logger = ref.watch(appLoggerProvider);
  final repository = ref.watch(logRepositoryProvider);

  final fromCore = core.logs.listen(
    (line) => unawaited(repository.append(line)),
    onError: (Object error) {
      logger.warn('core log stream failed: $error', tag: _tag);
    },
  );
  final fromApp = logger.lines.listen(
    (line) => unawaited(repository.append(line)),
  );

  ref.onDispose(() {
    unawaited(fromCore.cancel());
    unawaited(fromApp.cancel());
  });
});

/// The status the connect button draws.
final tunnelStatusProvider = Provider<TunnelStatus>((ref) {
  final action = ref.watch(tunnelControllerProvider);
  final failure = action.failure;
  if (failure != null) {
    return TunnelStatus.error(failure);
  }
  final reported =
      ref.watch(coreStatusProvider).value ?? const TunnelStatus.idle();
  if (action.isBusy && reported is TunnelIdle) {
    return const TunnelStatus.starting();
  }
  return reported;
});

/// Actions on the tunnel, plus whatever the last one produced.
final tunnelControllerProvider =
    NotifierProvider<TunnelController, TunnelActionState>(
  TunnelController.new,
);

/// What the last tunnel action left behind.
@immutable
class TunnelActionState {
  /// Creates the state.
  const TunnelActionState({
    this.isBusy = false,
    this.failure,
    this.notice,
    this.lastConfig,
  });

  /// Nothing has been tried yet.
  static const TunnelActionState initial = TunnelActionState();

  /// A start or stop call is in flight.
  final bool isBusy;

  /// The failure the last action produced, if it produced one.
  final CommyFailure? failure;

  /// A one-line success message worth showing once, e.g. the check result.
  final TunnelNotice? notice;

  /// The configuration handed to the core on the last successful start.
  ///
  /// Kept so the diagnostics screen can answer "what did you actually send",
  /// which is principle 3 of docs/00-vision.md. Rule R2: it is held in memory
  /// only and redacted before it reaches the screen.
  final CoreConfig? lastConfig;

  /// A copy with the given fields replaced.
  TunnelActionState copyWith({
    bool? isBusy,
    CommyFailure? failure,
    TunnelNotice? notice,
    CoreConfig? lastConfig,
    bool clearFailure = false,
    bool clearNotice = false,
  }) {
    return TunnelActionState(
      isBusy: isBusy ?? this.isBusy,
      failure: clearFailure ? null : failure ?? this.failure,
      notice: clearNotice ? null : notice ?? this.notice,
      lastConfig: lastConfig ?? this.lastConfig,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TunnelActionState &&
          other.isBusy == isBusy &&
          other.failure == failure &&
          other.notice == notice &&
          other.lastConfig == lastConfig;

  @override
  int get hashCode => Object.hash(isBusy, failure, notice, lastConfig);

  @override
  String toString() => 'TunnelActionState(busy: $isBusy, $failure)';
}

/// A transient message with no failure behind it.
enum TunnelNoticeKind {
  /// The reachability probe answered.
  checkPassed,

  /// The reachability probe did not answer.
  checkFailed,

  /// The outbound was switched inside a running core.
  switched,
}

/// A transient message and the one number or name it carries.
@immutable
class TunnelNotice {
  /// Creates the notice.
  const TunnelNotice(this.kind, {this.milliseconds, this.name});

  /// Which message to show.
  final TunnelNoticeKind kind;

  /// Round trip of the probe, when the notice is a check result.
  final int? milliseconds;

  /// Node name, when the notice is a switch.
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TunnelNotice &&
          other.kind == kind &&
          other.milliseconds == milliseconds &&
          other.name == name;

  @override
  int get hashCode => Object.hash(kind, milliseconds, name);

  @override
  String toString() => 'TunnelNotice(${kind.name})';
}

/// Connect, disconnect, switch and check.
class TunnelController extends Notifier<TunnelActionState> {
  @override
  TunnelActionState build() => TunnelActionState.initial;

  /// Starts the tunnel on [nodeId], or on the current selection.
  ///
  /// Returns `false` when there was nothing to connect to, so the caller can
  /// send the user to the import sheet instead of showing an error about a
  /// choice they never made.
  Future<bool> connect({String? nodeId}) async {
    final target = nodeId ?? ref.read(selectedNodeIdProvider).value;
    if (target == null) {
      return false;
    }
    if (state.isBusy) {
      return true;
    }
    state = state.copyWith(
      isBusy: true,
      clearFailure: true,
      clearNotice: true,
    );
    final logger = ref.read(appLoggerProvider);
    logger.info('connect requested', tag: _tag);

    final result = await ref.read(connectUseCaseProvider)(nodeId: target);
    final failure = result.failureOrNull;
    if (failure != null) {
      logger.error('connect failed: ${failure.code}', tag: _tag);
      state = state.copyWith(isBusy: false, failure: failure);
      return true;
    }
    await ref.read(selectedNodeIdProvider.notifier).select(target);
    state = state.copyWith(isBusy: false, lastConfig: _buildPreview(target));
    return true;
  }

  /// Stops the tunnel.
  Future<void> disconnect() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      isBusy: true,
      clearFailure: true,
      clearNotice: true,
    );
    final result = await ref.read(disconnectUseCaseProvider)();
    final failure = result.failureOrNull;
    state = state.copyWith(isBusy: false, failure: failure);
  }

  /// Connect or disconnect, whichever the current status calls for.
  ///
  /// `starting` counts as up: the tap on a spinning button is a cancel, which
  /// is what docs/05-ux-flows.md promises for that state.
  Future<bool> toggle() async {
    final shouldStop = switch (ref.read(tunnelStatusProvider)) {
      TunnelConnected() || TunnelChecking() || TunnelStarting() => true,
      TunnelIdle() || TunnelStopping() || TunnelError() => false,
    };
    if (shouldStop) {
      await disconnect();
      return true;
    }
    return connect();
  }

  /// Picks [node]. Switches the outbound in place when the tunnel is up.
  ///
  /// A restart would drop every open connection, which is exactly what
  /// docs/05-ux-flows.md forbids: "не отключаемся и не подключаемся заново".
  Future<void> selectNode(ProxyNode node) async {
    final isUp = switch (ref.read(tunnelStatusProvider)) {
      TunnelConnected() || TunnelChecking() => true,
      TunnelIdle() ||
      TunnelStarting() ||
      TunnelStopping() ||
      TunnelError() =>
        false,
    };
    if (!isUp) {
      await ref.read(selectedNodeIdProvider.notifier).select(node.id);
      return;
    }
    final result = await ref.read(switchNodeUseCaseProvider)(
      nodeId: node.id,
      outboundTag: SingBoxTags.forNode(node),
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      state = state.copyWith(failure: failure);
      return;
    }
    await ref.read(selectedNodeIdProvider.notifier).select(node.id);
    state = state.copyWith(
      clearFailure: true,
      notice: TunnelNotice(TunnelNoticeKind.switched, name: node.name),
    );
  }

  /// Runs the reachability probe behind the "Проверить" button.
  ///
  /// A live tunnel is not working internet: the server may have died, the
  /// quota may be spent, the provider may be filtering. Showing "connected"
  /// and staying silent is how the app gets blamed for the server.
  Future<void> check() async {
    final node = ref.read(selectedNodeProvider);
    if (node == null) {
      return;
    }
    state = state.copyWith(clearNotice: true, clearFailure: true);
    final result = await ref.read(checkReachabilityUseCaseProvider)(
      outboundTag: SingBoxTags.forNode(node),
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      state = state.copyWith(failure: failure);
      return;
    }
    final latency = result.valueOrNull;
    state = state.copyWith(
      notice: latency == null
          ? const TunnelNotice(TunnelNoticeKind.checkFailed)
          : TunnelNotice(
              TunnelNoticeKind.checkPassed,
              milliseconds: latency.inMilliseconds,
            ),
    );
  }

  /// Measures one node and stores the result.
  Future<void> measure(ProxyNode node) async {
    final result = await ref.read(measureLatencyUseCaseProvider)(
      nodeId: node.id,
      outboundTag: SingBoxTags.forNode(node),
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      state = state.copyWith(failure: failure);
    }
  }

  /// Measures every node in [nodes], one after another.
  ///
  /// Sequential on purpose: firing thirty probes at once through one tunnel
  /// measures the tunnel's queue, not the servers.
  Future<void> measureAll(List<ProxyNode> nodes) async {
    for (final node in nodes) {
      await measure(node);
    }
  }

  /// Drops the last failure, e.g. when the user dismisses the banner.
  void clearFailure() => state = state.copyWith(clearFailure: true);

  /// Drops the last notice once it has been shown.
  void clearNotice() => state = state.copyWith(clearNotice: true);

  /// Rebuilds the configuration that was just sent, for the diagnostics tab.
  ///
  /// Cheap, deterministic and read-only: it asks the same generator with the
  /// same inputs rather than keeping a second copy of the document alive.
  CoreConfig? _buildPreview(String nodeId) {
    final node = _nodeById(nodeId);
    if (node == null) {
      return null;
    }
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final routing =
        ref.read(routingPolicyProvider).value ?? RoutingPolicy.defaults;
    final dns = ref.read(dnsSettingsProvider).value ?? DnsSettings.defaults;
    final platform = ref.read(configPlatformProvider);
    final built = ref.read(configGeneratorProvider).build(
          node: node,
          routing: routing,
          dns: dns,
          settings: settings,
          includeClashApi: platform.allowsClashApi,
        );
    return built.valueOrNull;
  }

  ProxyNode? _nodeById(String id) {
    final all = ref.read(nodesProvider).value ?? const <ProxyNode>[];
    for (final node in all) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }
}
