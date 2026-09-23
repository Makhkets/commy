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

/// How often the app asks the core which member each group is pointed at.
///
/// Five seconds, and the number is picked against what actually moves: the
/// Auto group re-measures every five minutes and only switches when a member
/// comes back at least `autoGroupTolerance` better. This is not tracking
/// anything live — it is the delay between the core changing its mind and the
/// screen saying so.
const Duration _groupPoll = Duration(seconds: 5);

/// What the running core says its outbound groups are pointed at.
///
/// Polled, because there is nothing to subscribe to: libbox pushes status,
/// traffic, logs and connections, and answers about groups only when asked.
///
/// It asks nothing at all unless the user is on Auto and the tunnel is up.
/// With a server chosen by hand the app already knows the answer — it is the
/// one the user tapped — and a poll that answers a question nobody asked is
/// how a battery goes missing.
final proxyGroupsProvider = StreamProvider<List<ProxyGroup>>((ref) {
  final core = ref.watch(coreClientProvider);
  final isUp = switch (ref.watch(coreStatusProvider).value) {
    TunnelConnected() || TunnelChecking() => true,
    _ => false,
  };
  if (!isUp || !ref.watch(autoSelectedProvider)) {
    return Stream<List<ProxyGroup>>.value(const <ProxyGroup>[]);
  }

  final controller = StreamController<List<ProxyGroup>>();
  var asking = false;
  Future<void> ask() async {
    // One question at a time: a channel that answers slower than the interval
    // would otherwise queue calls until it answers them all at once.
    if (asking || controller.isClosed) {
      return;
    }
    asking = true;
    try {
      final groups = await core.proxies();
      if (!controller.isClosed) {
        controller.add(groups);
      }
    } on Object catch (error) {
      // Deliberately not an error state. This drives one line of a row; a
      // core that will not answer must not turn the server list into a
      // failure screen.
      ref.read(appLoggerProvider).debug('proxies failed: $error', tag: _tag);
    } finally {
      asking = false;
    }
  }

  final timer = Timer.periodic(_groupPoll, (_) => unawaited(ask()));
  unawaited(ask());
  ref.onDispose(() {
    timer.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

/// The server the Auto group is sending traffic through right now.
///
/// `null` until the core has answered, and `null` for good on a tunnel that
/// is down: Auto without a running core is a preference, not a destination.
final autoNodeProvider = Provider<ProxyNode?>((ref) {
  final groups = ref.watch(proxyGroupsProvider).value ?? const <ProxyGroup>[];
  String? id;
  for (final group in groups) {
    final member = group.now;
    if (group.tag == SingBoxTags.autoGroup && member != null) {
      id = SingBoxTags.nodeIdOf(member);
      break;
    }
  }
  if (id == null) {
    return null;
  }
  for (final node in ref.watch(nodesProvider).value ?? const <ProxyNode>[]) {
    if (node.id == id) {
      return node;
    }
  }
  return null;
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
  // The drain runs once because the three providers above never rebuild.
  // Queue item #17 gave them disposal, not a new lifecycle: they are closed
  // with the scope and never invalidated inside one. The day one of them is,
  // the backlog would be replayed — the guard belongs with that change.
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
///
/// `autoSelect` is the one field the builder reads that is deliberately absent.
/// `TunnelController` applies it itself, and only rebuilds when the running
/// core genuinely lacks the group; listing it here would turn every tap on a
/// server row into a restart, because turning Auto off is part of that tap.
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

  /// The choice of server was handed to the core's own latency group.
  switchedToAuto,

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

  /// Starts the tunnel on [nodeId], or on the current selection, or — when
  /// nothing was ever picked — on the first server there is.
  ///
  /// That last fallback is what the button owes a first-time user. Someone who
  /// imported one link and pressed the only large control on the screen has
  /// made their choice; answering with nothing, because no row had been
  /// tapped, read on a device as a dead button. The server it lands on becomes
  /// the selection, so the chip under the button names it the moment the
  /// tunnel is up.
  ///
  /// Returns `false` only when there is no server at all, so the caller can
  /// send the user to the import sheet instead of showing an error about a
  /// choice they never made.
  Future<bool> connect({String? nodeId}) async {
    final target = nodeId ?? await _connectTarget();
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
      ..info('connect requested: ${_describe(target)}', tag: _tag);

    final result = await ref.read(connectUseCaseProvider)(nodeId: target);
    final failure = result.failureOrNull;
    if (failure != null) {
      // The failure itself, not just its code. The code is what the screen
      // translates; the detail inside it — which resolver, which field, which
      // exception — is the only part that says what to change, and dropping it
      // here is what left the log with nothing to read after a failed connect.
      logger.error('connect failed: $failure', tag: _tag);
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
  ///
  /// Tapping a server is also how Auto is turned off, and the order below is
  /// the reason this method is not three lines. Auto is ended **last**, once
  /// the new server is the stored one: turned off first, the mark would leave
  /// Auto, land for a frame on whichever server the list happened to lead
  /// with, and only then reach the one under the finger. A switch that failed
  /// leaves Auto on, because nothing moved.
  ///
  /// No rebuild when the running document holds the server, which is the usual
  /// case: every server known at start is in the selector, so pointing it at
  /// one of them is the whole change, and the Auto group stays in that document
  /// until the next start, unused and unpointed at.
  ///
  /// A server the document does not hold is the other case, and it is not
  /// rare: one imported while the tunnel was up, or one a subscription refresh
  /// brought in an hour into the session. The core answers a `select` of a tag
  /// it has never heard of with an error, and the user — who did nothing but
  /// tap a server they can see in the list — got "could not switch" until they
  /// thought of disconnecting first. So the core is asked, as [selectAuto]
  /// asks it, and the document is rebuilt around the new server when it has to
  /// be. `reload` keeps the TUN device; it is a pause, not a window (rule R6).
  Future<void> selectNode(ProxyNode node) async {
    if (!_isUp) {
      await ref.read(selectedNodeIdProvider.notifier).select(node.id);
      await _setAutoSelect(enabled: false);
      return;
    }
    final tag = SingBoxTags.forNode(node);
    if (!await _runningCoreHolds(tag)) {
      final previous = ref.read(selectedNodeIdProvider).value;
      await ref.read(selectedNodeIdProvider.notifier).select(node.id);
      await reload();
      if (state.failure != null) {
        // Nothing moved: the tunnel still runs through the old server, and a
        // list that marks the new one would be lying about where traffic goes.
        if (previous != null) {
          await ref.read(selectedNodeIdProvider.notifier).select(previous);
        }
        return;
      }
      await _setAutoSelect(enabled: false);
      state = state.copyWith(
        notice: TunnelNotice(
          TunnelNoticeKind.switched,
          name: NodeLabel.of(node).text,
        ),
      );
      return;
    }
    final result = await ref.read(switchNodeUseCaseProvider)(
      nodeId: node.id,
      outboundTag: tag,
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      state = state.copyWith(failure: failure);
      return;
    }
    await ref.read(selectedNodeIdProvider.notifier).select(node.id);
    await _setAutoSelect(enabled: false);
    state = state.copyWith(
      clearFailure: true,
      notice: TunnelNotice(
        TunnelNoticeKind.switched,
        name: NodeLabel.of(node).text,
      ),
    );
  }

  /// Hands the choice of server to the core's own latency group.
  ///
  /// Auto is part of the document, not a runtime flag: a core started without
  /// it has no such outbound for the selector to point at. So the running core
  /// is asked first and rebuilt only when the group is genuinely missing —
  /// which makes coming back to Auto inside one session a switch rather than a
  /// restart, and every open connection survives it.
  ///
  /// The stored selection is left alone. It is the server the list leads with
  /// and the one the user returns to when they turn Auto off; overwriting it
  /// with whatever the core happens to prefer this minute would quietly lose
  /// the choice they made by hand.
  Future<void> selectAuto() async {
    await _setAutoSelect(enabled: true);
    if (!_isUp) {
      return;
    }
    final nodeId = ref.read(selectedNodeIdProvider).value;
    if (nodeId == null || await _autoGroup() == null) {
      await reload();
      return;
    }
    final result = await ref.read(switchNodeUseCaseProvider)(
      nodeId: nodeId,
      outboundTag: SingBoxTags.autoGroup,
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      state = state.copyWith(failure: failure);
      return;
    }
    state = state.copyWith(
      clearFailure: true,
      notice: const TunnelNotice(TunnelNoticeKind.switchedToAuto),
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
      logger.error('reload failed: $failure', tag: _tag);
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
  ///
  /// What gets measured is the outbound traffic actually leaves through, which
  /// on Auto is the core's pick and not the server the user last tapped. A
  /// check that answers for a different server than the one carrying the
  /// traffic is worse than no check at all.
  Future<void> check({bool includeIp = false}) async {
    final tag = await _liveOutboundTag();
    if (tag == null) {
      return;
    }
    state = state.copyWith(
      isChecking: true,
      clearNotice: true,
      clearFailure: true,
    );
    final result = await ref.read(checkReachabilityUseCaseProvider)(
      outboundTag: tag,
    );
    final logger = ref.read(appLoggerProvider);
    final failure = result.failureOrNull;
    if (failure != null) {
      logger.error(
        'reachability check failed through $tag: $failure',
        tag: _tag,
      );
      state = state.copyWith(isChecking: false, failure: failure);
      return;
    }
    final latency = result.valueOrNull;
    if (latency == null) {
      // The tunnel is up and nothing came back through it. This is the exact
      // shape of "connected but the internet does not work", and the log is
      // where the next question gets answered — so it says so here rather than
      // only as a toast the user has already dismissed.
      logger.warn(
        'reachability check found no way out through $tag; the tunnel is up '
        'but the probe did not come back',
        tag: _tag,
      );
      state = state.copyWith(
        isChecking: false,
        notice: const TunnelNotice(TunnelNoticeKind.checkFailed),
      );
      return;
    }
    final milliseconds = latency.inMilliseconds;
    logger.info(
      'reachability check passed through $tag in ${milliseconds}ms',
      tag: _tag,
    );
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
      logger.warn('ip check failed: $ipFailure', tag: _tag);
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

  /// Drops the last failure, e.g. when the user dismisses the banner.
  void clearFailure() => state = state.copyWith(clearFailure: true);

  /// Drops the last notice once it has been shown.
  void clearNotice() => state = state.copyWith(clearNotice: true);

  /// Writes the Auto setting, and only when it actually changes.
  ///
  /// Not through `SettingsController`: this is the tunnel's half of the same
  /// choice, and routing it through the settings screen's notifier would put a
  /// failure banner about servers on a screen about preferences.
  ///
  /// Deliberately outside `_CoreInputs`, so the debounced reload never sees
  /// it. Both directions are applied here by hand — see [selectAuto] and
  /// [selectNode] — because a reload on this field would turn every tap on a
  /// server row into a core restart, which is the one thing switching inside
  /// the selector exists to avoid.
  Future<void> _setAutoSelect({required bool enabled}) async {
    final repository = ref.read(settingsRepositoryProvider);
    final read = await repository.read();
    final current = read.valueOrNull ?? AppSettings.defaults;
    if (current.autoSelect == enabled) {
      return;
    }
    final written = await repository.write(
      current.copyWith(autoSelect: enabled),
    );
    final failure = written.failureOrNull;
    if (failure != null) {
      state = state.copyWith(failure: failure);
    }
  }

  /// Whether the selector of the running core has [tag] among its members.
  ///
  /// A core that will not answer counts as one that has it: the switch is then
  /// tried the ordinary way, and its own failure is the one that gets shown.
  /// Rebuilding on a guess would restart a core that may be perfectly fine.
  Future<bool> _runningCoreHolds(String tag) async {
    try {
      for (final group in await ref.read(coreClientProvider).proxies()) {
        if (group.tag == SingBoxTags.proxyGroup) {
          return group.all.contains(tag);
        }
      }
    } on Object catch (error) {
      ref.read(appLoggerProvider).debug('proxies failed: $error', tag: _tag);
    }
    return true;
  }

  /// The Auto group as the running core reports it, or `null` when it has none.
  ///
  /// A core that will not answer counts as one without the group: the caller
  /// then rebuilds, which is the answer that works either way.
  Future<ProxyGroup?> _autoGroup() async {
    try {
      for (final group in await ref.read(coreClientProvider).proxies()) {
        if (group.tag == SingBoxTags.autoGroup) {
          return group;
        }
      }
    } on Object catch (error) {
      ref.read(appLoggerProvider).debug('proxies failed: $error', tag: _tag);
    }
    return null;
  }

  /// The outbound traffic is leaving through right now, or `null`.
  ///
  /// On Auto the core is asked rather than guessed at: its answer is a member
  /// tag, and it is used as it comes instead of being resolved to a node and
  /// back, so a server deleted from the list a moment ago still measures the
  /// outbound that is carrying the traffic.
  Future<String?> _liveOutboundTag() async {
    if (ref.read(autoSelectedProvider)) {
      final picked = (await _autoGroup())?.now;
      if (picked != null) {
        return picked;
      }
    }
    final node = ref.read(selectedNodeProvider);
    return node == null ? null : SingBoxTags.forNode(node);
  }

  /// The server a start begins from when nothing was ever picked.
  ///
  /// On Auto the document needs a node to lead with even though the selector
  /// defaults to the group, and a user who has only ever tapped Auto has picked
  /// none. With Auto off it is the same answer for a plainer reason: there are
  /// servers, the user asked to connect, and the first one in the list is the
  /// one they are looking at. The core reorders by latency on Auto the moment
  /// it has measured them; off Auto the user can switch without reconnecting.
  /// The server a connect with no explicit choice lands on: the selection,
  /// or the first server there is.
  ///
  /// Awaited rather than read. A connect that arrives with the process — the
  /// notification that says the tunnel is down, the Quick Settings tile on a
  /// cold app — gets here before the database has answered, and a
  /// synchronous read then finds neither a selection nor a single server and
  /// returns as if there were nothing to connect to. On a device that was the
  /// tap on "open the app to bring the tunnel up" opening the app and leaving
  /// the tunnel down, with nothing in the log but the intent itself.
  ///
  /// Both are listened to for the length of the wait: a provider nobody
  /// listens to is paused, and a paused stream never delivers the first value
  /// its `future` is waiting for.
  Future<String?> _connectTarget() async {
    final selection = ref.listen(selectedNodeIdProvider, (_, __) {});
    final servers = ref.listen(nodesProvider, (_, __) {});
    try {
      try {
        final selected = await ref.read(selectedNodeIdProvider.future);
        if (selected != null) {
          return selected;
        }
      } on Object {
        // A selection that cannot be read is no selection: fall through to
        // the first server, as a user who never picked one gets.
      }
      final all = await ref.read(nodesProvider.future);
      return all.isEmpty ? null : all.first.id;
    } on Object {
      return null;
    } finally {
      selection.close();
      servers.close();
    }
  }

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

  /// One line naming the server a connect is about to use.
  ///
  /// Name, protocol and address — the three things that identify which of the
  /// user's servers this was, and no more than that. The credentials stay out
  /// by construction rather than by redaction: nothing here reads them.
  String _describe(String nodeId) {
    final node = _nodeById(nodeId);
    if (node == null) {
      return nodeId;
    }
    return '${NodeLabel.of(node).text} · ${node.protocol.wireName} · '
        '${node.host}:${node.port}';
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
