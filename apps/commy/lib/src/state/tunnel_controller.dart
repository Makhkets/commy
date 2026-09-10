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

import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
///
/// The logger's ring buffer is replayed before the stream is followed.
/// `AppLogger.lines` is broadcast, so a late subscriber sees nothing written
/// before it — and the lines written before this provider builds are exactly
/// the ones a bug report opens with: the boot warning from `main()`, and the
/// factory's "running on the fake core" note, which is written *inside* the
/// `coreClientProvider` watch below. `AppLogger` prescribes the order used
/// here: read `buffer` once on attach, then follow `lines`.
final logPumpProvider = Provider<void>((ref) {
  final core = ref.watch(coreClientProvider);
  final logger = ref.watch(appLoggerProvider);
  final repository = ref.watch(logRepositoryProvider);

  // No deduplication, on purpose. `AppLogger.add` is synchronous and there is
  // no await between this snapshot and the subscription below, so a line is
  // either in the backlog or on the stream, never both. A check by `LogLine`
  // equality would only ever drop a line the app genuinely wrote twice.
  //
  // The drain runs once because the three providers above never rebuild. If
  // one of them ever does (task #17 moves their lifecycle), the backlog would
  // be replayed again — the guard belongs with that change, not here.
  final backlog = logger.buffer;
  if (backlog.isNotEmpty) {
    unawaited(repository.appendAll(backlog));
  }

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
  // `checking` is the one state the core never reports. It is derived here,
  // which is exactly the asymmetry scripts/check_wire_contract.py records when
  // it lists `checking` under DART_ONLY_STATES.
  if (action.isChecking && reported is TunnelConnected) {
    return TunnelStatus.checking(
      since: reported.since,
      nodeId: reported.nodeId,
    );
  }
  return reported;
});

/// Probes reachability once each time the tunnel comes up.
///
/// docs/05-ux-flows.md puts `checking` between `connected` and "готово", and
/// says why: a raised tunnel is not working internet — the server may be dead,
/// the quota spent, the provider filtering. Without this the state exists in
/// the domain, in the codec and in the button, and never once happens on a
/// device.
///
/// Watched from the root, like the log pump: the probe belongs to the
/// connection, not to whichever screen is on top when it comes up.
final autoCheckProvider = Provider<void>((ref) {
  // Keyed on `since` rather than a bool: reconnecting produces a new timestamp,
  // so each connection is probed exactly once and a rebuild probes none.
  DateTime? probed;
  ref.listen<AsyncValue<TunnelStatus>>(coreStatusProvider, (previous, next) {
    final status = next.value;
    if (status is! TunnelConnected) {
      probed = null;
      return;
    }
    if (probed == status.since) {
      return;
    }
    probed = status.since;
    unawaited(ref.read(tunnelControllerProvider.notifier).check());
  });
});

/// Connects on launch when the user asked for it.
///
/// Deliberately decided **once**, off the first settled read of both settings
/// and the stored selection. Reacting to every later change would turn the
/// switch into "connect the moment this is enabled", which is not what
/// "автоподключение при запуске" says on the settings screen.
final autoConnectProvider = Provider<void>((ref) {
  var decided = false;
  void consider() {
    if (decided) {
      return;
    }
    final settings = ref.read(settingsProvider).value;
    final selected = ref.read(selectedNodeIdProvider);
    if (settings == null || selected.isLoading) {
      return;
    }
    decided = true;
    final nodeId = selected.value;
    if (!settings.autoConnect || nodeId == null) {
      return;
    }
    unawaited(
      ref.read(tunnelControllerProvider.notifier).connect(nodeId: nodeId),
    );
  }

  ref
    ..listen<AsyncValue<AppSettings>>(settingsProvider, (_, __) => consider())
    ..listen<AsyncValue<String?>>(
      selectedNodeIdProvider,
      (_, __) => consider(),
    );
  consider();
});

/// How long a burst of edits is allowed to settle before one reload.
///
/// Three switches flipped in a row should cost the core one restart, not
/// three. Long enough to cover a hand moving between rows, short enough that
/// the change still feels immediate.
const Duration _reloadSettle = Duration(milliseconds: 400);

/// The settings the configuration builder actually reads, and nothing else.
///
/// A record, so equality is structural and a field the builder starts reading
/// has exactly one place to be added. Everything not listed — theme, language,
/// the hide-unavailable filter, the launch and boot switches — is the app's
/// business and must never restart the core.
typedef _CoreInputs = ({
  bool allowLan,
  String ipCheckUrl,
  String latencyProbeUrl,
  LogLevel logLevel,
  int mixedPort,
  TunStack tunStack,
});

_CoreInputs _coreInputsOf(AppSettings settings) => (
      allowLan: settings.allowLan,
      // The builder opens the loopback inbound off this one (E-1).
      ipCheckUrl: settings.ipCheckUrl,
      latencyProbeUrl: settings.latencyProbeUrl,
      logLevel: settings.logLevel,
      mixedPort: settings.mixedPort,
      tunStack: settings.tunStack,
    );

/// Applies routing, DNS and settings changes to a running tunnel.
///
/// Before this, an edit on the routing screen was visible only after the next
/// reconnect, and nothing said so. Now the change is rebuilt into a whole
/// configuration and handed to the running core through `reload`, which
/// keeps the TUN device (rule R6: a pause, not a window).
///
/// Three things keep it from firing when it should not:
///
/// * only the settings the builder reads are compared ([_CoreInputs]) — a
///   theme or language change must not restart the core;
/// * the tunnel has to be up. Down, the next connect reads the same stores.
///   Starting, the change is remembered and applied once the core reports
///   `connected`, because the start in flight was built from the old values;
/// * edits are coalesced over [_reloadSettle].
///
/// Watched from the root, like the log pump: a routing edit is made on one
/// screen and has to land whichever screen is on top when the timer fires.
final liveReloadProvider = Provider<void>((ref) {
  Timer? settle;
  var pending = false;

  void schedule() {
    pending = false;
    settle?.cancel();
    settle = Timer(_reloadSettle, () {
      unawaited(ref.read(tunnelControllerProvider.notifier).reload());
    });
  }

  void onChange() {
    switch (ref.read(coreStatusProvider).value) {
      case TunnelConnected() || TunnelChecking():
        schedule();
      case TunnelStarting():
        pending = true;
      case TunnelIdle() || TunnelStopping() || TunnelError() || null:
        pending = false;
    }
  }

  ref
    ..onDispose(() => settle?.cancel())
    ..listen<AsyncValue<RoutingPolicy>>(routingPolicyProvider,
        (previous, next) {
      final before = previous?.value;
      final after = next.value;
      // The first value is a load, not a change.
      if (before != null && after != null && before != after) {
        onChange();
      }
    })
    ..listen<AsyncValue<DnsSettings>>(dnsSettingsProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before != null && after != null && before != after) {
        onChange();
      }
    })
    ..listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before != null &&
          after != null &&
          _coreInputsOf(before) != _coreInputsOf(after)) {
        onChange();
      }
    })
    ..listen<AsyncValue<TunnelStatus>>(coreStatusProvider, (previous, next) {
      if (pending &&
          next.value is TunnelConnected &&
          previous?.value is TunnelStarting) {
        schedule();
      }
    });
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
    this.isChecking = false,
    this.failure,
    this.notice,
    this.lastConfig,
  });

  /// Nothing has been tried yet.
  static const TunnelActionState initial = TunnelActionState();

  /// A start or stop call is in flight.
  final bool isBusy;

  /// A reachability probe is in flight.
  ///
  /// Kept apart from [isBusy]: the tunnel is up and usable while this is set,
  /// so the button must stay a "disconnect", not become a spinner.
  final bool isChecking;

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
    bool? isChecking,
    CommyFailure? failure,
    TunnelNotice? notice,
    CoreConfig? lastConfig,
    bool clearFailure = false,
    bool clearNotice = false,
  }) {
    return TunnelActionState(
      isBusy: isBusy ?? this.isBusy,
      isChecking: isChecking ?? this.isChecking,
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
          other.isChecking == isChecking &&
          other.failure == failure &&
          other.notice == notice &&
          other.lastConfig == lastConfig;

  @override
  int get hashCode =>
      Object.hash(isBusy, isChecking, failure, notice, lastConfig);

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

  /// The running core took a changed configuration.
  reloaded,

  /// The reachability probe passed, but the IP check (E-1) did not answer.
  ipCheckFailed,
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

  /// Node name when the notice is a switch; the exit address when it is a
  /// passed check with the IP check on.
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
    final logger = ref.read(appLoggerProvider)
      ..info('connect requested', tag: _tag);

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
  ///
  /// It reads `coreStatusProvider`, not `tunnelStatusProvider`. The latter
  /// folds this notifier's own state back in, so reading it from here is a
  /// cycle — and Riverpod says so at runtime rather than at compile time,
  /// which is exactly the kind of bug that only shows up under a user's
  /// finger.
  Future<bool> toggle() async {
    final shouldStop = switch (_reportedStatus) {
      TunnelConnected() || TunnelChecking() || TunnelStarting() => true,
      TunnelIdle() || TunnelStopping() || TunnelError() => false,
    };
    if (shouldStop) {
      await disconnect();
      return true;
    }
    return connect();
  }

  /// What the core last said, with no local state folded in.
  TunnelStatus get _reportedStatus =>
      ref.read(coreStatusProvider).value ?? const TunnelStatus.idle();

  /// Whether the core is running and usable. `starting` is not: nothing can
  /// be switched or reloaded inside a core that has not come up yet.
  bool get _isUp => switch (_reportedStatus) {
        TunnelConnected() || TunnelChecking() => true,
        TunnelIdle() ||
        TunnelStarting() ||
        TunnelStopping() ||
        TunnelError() =>
          false,
      };

  /// Picks [node]. Switches the outbound in place when the tunnel is up.
  ///
  /// A restart would drop every open connection, which is exactly what
  /// docs/05-ux-flows.md forbids: "не отключаемся и не подключаемся заново".
  Future<void> selectNode(ProxyNode node) async {
    if (!_isUp) {
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

  /// Applies the current routing, DNS and settings to the running core.
  ///
  /// Whole, not patched: the same document a connect would send, handed to
  /// `CoreClient.reload`, which keeps the TUN device. Nothing happens unless
  /// the tunnel is up — down, the next connect builds from the same stores.
  /// The core reports `starting` and then `connected` again, so the
  /// reachability probe runs once more against the new configuration.
  Future<void> reload() async {
    final nodeId = ref.read(selectedNodeIdProvider).value;
    if (nodeId == null || state.isBusy || !_isUp) {
      return;
    }
    state = state.copyWith(
      isBusy: true,
      clearFailure: true,
      clearNotice: true,
    );
    final logger = ref.read(appLoggerProvider)
      ..info('reload requested', tag: _tag);

    final result = await ref.read(reloadUseCaseProvider)(nodeId: nodeId);
    final failure = result.failureOrNull;
    if (failure != null) {
      logger.error('reload failed: ${failure.code}', tag: _tag);
      state = state.copyWith(isBusy: false, failure: failure);
      return;
    }
    state = state.copyWith(
      isBusy: false,
      lastConfig: _buildPreview(nodeId),
      notice: const TunnelNotice(TunnelNoticeKind.reloaded),
    );
  }

  /// Runs the reachability probe behind the "Проверить" button.
  ///
  /// A live tunnel is not working internet: the server may have died, the
  /// quota may be spent, the provider may be filtering. Showing "connected"
  /// and staying silent is how the app gets blamed for the server.
  ///
  /// [includeIp] adds the external IP check — exception E-1 of
  /// docs/09-security-privacy.md, allowed **by button press only**. The
  /// automatic probe after a connect leaves it `false`, and nothing else may
  /// pass `true`. With the feature off the flag changes nothing: the use
  /// case reads the setting and answers nothing.
  Future<void> check({bool includeIp = false}) async {
    final node = ref.read(selectedNodeProvider);
    if (node == null) {
      return;
    }
    state = state.copyWith(
      isChecking: true,
      clearNotice: true,
      clearFailure: true,
    );
    final result = await ref.read(checkReachabilityUseCaseProvider)(
      outboundTag: SingBoxTags.forNode(node),
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      state = state.copyWith(isChecking: false, failure: failure);
      return;
    }
    final latency = result.valueOrNull;
    if (latency == null) {
      state = state.copyWith(
        isChecking: false,
        notice: const TunnelNotice(TunnelNoticeKind.checkFailed),
      );
      return;
    }
    final milliseconds = latency.inMilliseconds;
    if (!includeIp) {
      state = state.copyWith(
        isChecking: false,
        notice: TunnelNotice(
          TunnelNoticeKind.checkPassed,
          milliseconds: milliseconds,
        ),
      );
      return;
    }
    // Still `isChecking`: the spinner covers both steps, and the address
    // is the second one.
    final ipResult = await ref.read(checkIpUseCaseProvider)();
    final ipFailure = ipResult.failureOrNull;
    if (ipFailure != null) {
      ref
          .read(appLoggerProvider)
          .warn('ip check failed: ${ipFailure.code}', tag: _tag);
      state = state.copyWith(
        isChecking: false,
        notice: TunnelNotice(
          TunnelNoticeKind.ipCheckFailed,
          milliseconds: milliseconds,
        ),
      );
      return;
    }
    state = state.copyWith(
      isChecking: false,
      notice: TunnelNotice(
        TunnelNoticeKind.checkPassed,
        milliseconds: milliseconds,
        name: ipResult.valueOrNull?.label,
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
