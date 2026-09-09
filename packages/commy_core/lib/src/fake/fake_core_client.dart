import 'dart:async';

import 'package:commy_core/src/core_client_exception.dart';
import 'package:commy_core/src/fake/fake_core_step.dart';
import 'package:commy_core/src/logging/app_logger.dart';
import 'package:commy_domain/commy_domain.dart';

/// A complete in-memory `CoreClient` that carries no traffic.
///
/// It exists for two jobs, and both of them are load-bearing.
///
/// **Testing the connect flow.** The interesting bugs in this app are in the
/// state machine — a button stuck on `connecting`, a `stopping` that never
/// reaches `idle`, an error the screen swallows. None of that needs a tunnel,
/// and requiring one would mean these paths are only ever exercised by hand on
/// a device.
///
/// **Running the app on desktop.** The privileged helpers for Windows, macOS
/// and Linux are later milestones (docs/07-roadmap.md). Until they land,
/// `CoreClientFactory` hands the app this, so every screen except the tunnel
/// itself can be built and reviewed on the machine it is written on.
///
/// It walks the real six-state machine — `idle` → `starting` → `connected` →
/// `checking` → back to `connected`, and `stopping` → `idle` on the way down —
/// emits synthetic traffic, logs and connection snapshots on a timer, and can
/// be told to fail any call through [failOn]. Nothing here touches the network:
/// rule R1 holds trivially, because there is no socket in this file.
class FakeCoreClient implements CoreClient {
  /// Creates the fake.
  ///
  /// Every duration is injectable so a test can run the whole machine in a few
  /// milliseconds while the app uses lifelike ones. [seed] makes the synthetic
  /// traffic reproducible: the same seed always produces the same series, so a
  /// golden test of the traffic chart is possible at all.
  FakeCoreClient({
    AppLogger? logger,
    Duration startDelay = const Duration(milliseconds: 600),
    Duration checkDelay = const Duration(milliseconds: 900),
    Duration stopDelay = const Duration(milliseconds: 250),
    Duration tick = const Duration(seconds: 1),
    Duration latency = const Duration(milliseconds: 137),
    List<ProxyGroup>? groups,
    int seed = defaultSeed,
    DateTime Function()? clock,
  })  : _logger = logger,
        _startDelay = startDelay,
        _checkDelay = checkDelay,
        _stopDelay = stopDelay,
        _tick = tick,
        _latency = latency,
        _groups = List<ProxyGroup>.of(groups ?? defaultGroups),
        _seed = seed,
        _random = seed,
        _clock = clock ?? DateTime.now;

  /// Seed used when the caller did not pick one.
  static const int defaultSeed = 20260804;

  /// Tag the fake's own log lines carry.
  static const String logTag = 'core.fake';

  /// The groups a fresh fake reports: one selector with three members.
  ///
  /// The tags are obviously synthetic on purpose. A fake that reports plausible
  /// real node names is a fake somebody eventually mistakes for the real thing.
  static List<ProxyGroup> get defaultGroups => const <ProxyGroup>[
        ProxyGroup(
          tag: SwitchNodeUseCase.defaultGroupTag,
          type: 'selector',
          now: 'node-alpha',
          all: <String>['node-alpha', 'node-beta', 'node-gamma'],
        ),
      ];

  final AppLogger? _logger;
  final Duration _startDelay;
  final Duration _checkDelay;
  final Duration _stopDelay;
  final Duration _tick;
  final Duration _latency;
  final List<ProxyGroup> _groups;
  final int _seed;
  final DateTime Function() _clock;

  final Map<FakeCoreStep, CommyFailure> _failures =
      <FakeCoreStep, CommyFailure>{};
  final Map<String, Duration?> _latencies = <String, Duration?>{};

  final StreamController<TunnelStatus> _statusController =
      StreamController<TunnelStatus>.broadcast();
  final StreamController<TrafficSample> _trafficController =
      StreamController<TrafficSample>.broadcast();
  final StreamController<LogLine> _logsController =
      StreamController<LogLine>.broadcast();
  final StreamController<List<ConnectionInfo>> _connectionsController =
      StreamController<List<ConnectionInfo>>.broadcast();

  TunnelStatus _status = const TunnelStatus.idle();
  Timer? _startTimer;
  Timer? _checkTimer;
  Timer? _stopTimer;
  Timer? _ticker;
  DateTime? _since;
  String? _nodeId;
  int _random;
  int _uplinkTotal = 0;
  int _downlinkTotal = 0;
  int _ticks = 0;
  bool _running = false;
  bool _disposed = false;

  /// The state the fake is in right now, without subscribing.
  TunnelStatus get currentStatus => _status;

  /// Whether the fake considers the tunnel up.
  bool get isRunning => _running;

  /// The last configuration handed to [start] or [reload].
  CoreConfig? lastConfig;

  /// How many times [start] has been called, including the idempotent ones.
  int startCalls = 0;

  /// How many times [stop] has been called.
  int stopCalls = 0;

  @override
  Stream<TunnelStatus> get status => Stream<TunnelStatus>.multi(
        (controller) {
          // The protocol requires the native side to answer `onListen` with the
          // current state, so that a hot restart does not paint `idle` over a
          // live tunnel. The fake owes callers the same promise.
          controller.add(_status);
          final subscription = _statusController.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
          controller.onCancel = subscription.cancel;
        },
        isBroadcast: true,
      );

  @override
  Stream<TrafficSample> get traffic => _trafficController.stream;

  @override
  Stream<LogLine> get logs => _logsController.stream;

  @override
  Stream<List<ConnectionInfo>> get connections =>
      _connectionsController.stream;

  /// Makes [step] throw [failure] until [succeedOn] or [clearFailures].
  ///
  /// Failing `start` or `reload` also drives the state machine into `error`,
  /// which is what the native side does when the user declines the VPN prompt.
  void failOn(FakeCoreStep step, CommyFailure failure) =>
      _failures[step] = failure;

  /// Removes the failure configured for [step].
  void succeedOn(FakeCoreStep step) => _failures.remove(step);

  /// Removes every configured failure.
  void clearFailures() => _failures.clear();

  /// Fixes what [urlTest] answers for [tag]. `null` means "did not come back".
  void setLatency(String tag, Duration? value) => _latencies[tag] = value;

  /// Simulates the core dying underneath a running tunnel.
  ///
  /// This is manual scenario 9: an external kill, a Go panic, a `serviceStop`
  /// nobody asked for. The tunnel must land in `error`, not sit in `connected`
  /// pretending to carry traffic.
  void crash([CommyFailure failure = const CoreCrashedFailure('')]) {
    _cancelTimers();
    _running = false;
    _since = null;
    _emit(TunnelStatus.error(failure));
  }

  /// Rewinds the fake to a fresh `idle`, keeping the configured failures.
  void reset() {
    _cancelTimers();
    _running = false;
    _since = null;
    _nodeId = null;
    _random = _seed;
    _uplinkTotal = 0;
    _downlinkTotal = 0;
    _ticks = 0;
    startCalls = 0;
    stopCalls = 0;
    lastConfig = null;
    _emit(const TunnelStatus.idle());
  }

  @override
  Future<void> start(CoreConfig config) async {
    startCalls++;
    _guard(FakeCoreStep.start, resetsState: true);
    lastConfig = config;
    if (_running) {
      // Idempotent by contract: a second start does not raise a second tunnel.
      _logger?.debug('start: already running', tag: logTag);
      return;
    }
    _running = true;
    _cancelTimers();
    _emit(const TunnelStatus.starting());
    _startTimer = Timer(_startDelay, _onStarted);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _guard(FakeCoreStep.stop);
    if (!_running) {
      // Idempotent by contract: stopping a stopped tunnel is a success.
      return;
    }
    _running = false;
    _cancelTimers();
    _emit(const TunnelStatus.stopping());
    _stopTimer = Timer(_stopDelay, () {
      _since = null;
      _emit(const TunnelStatus.idle());
    });
  }

  @override
  Future<void> reload(CoreConfig config) async {
    _guard(FakeCoreStep.reload, resetsState: true);
    _requireRunning();
    lastConfig = config;
    _cancelTimers();
    _emit(const TunnelStatus.starting());
    _startTimer = Timer(_startDelay, _onStarted);
  }

  @override
  Future<void> select(String group, String tag) async {
    _guard(FakeCoreStep.select);
    _requireRunning();
    final index = _groups.indexWhere((candidate) => candidate.tag == group);
    if (index < 0 || !_groups[index].all.contains(tag)) {
      throw CoreClientException(
        ConfigInvalidFailure('No outbound "$tag" in group "$group"'),
      );
    }
    _groups[index] = _groups[index].copyWith(now: tag);
    _nodeId = tag;
    _note(LogLevel.info, 'switched outbound to $tag');
    final since = _since;
    if (since != null) {
      _emit(TunnelStatus.connected(since: since, nodeId: tag));
    }
  }

  @override
  Future<Duration?> urlTest(String tag, Uri probe) async {
    _guard(FakeCoreStep.urlTest);
    _requireRunning();
    final measured =
        _latencies.containsKey(tag) ? _latencies[tag] : _latency;
    _note(
      LogLevel.debug,
      'urltest $tag via ${probe.host}: '
      '${measured == null ? 'timeout' : '${measured.inMilliseconds}ms'}',
    );
    return measured;
  }

  @override
  Future<List<ProxyGroup>> proxies() async {
    _guard(FakeCoreStep.proxies);
    // A stopped core answers with an empty list, not with an error.
    return _running ? List<ProxyGroup>.unmodifiable(_groups) : const [];
  }

  /// Closes every stream and cancels every timer.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelTimers();
    await _statusController.close();
    await _trafficController.close();
    await _logsController.close();
    await _connectionsController.close();
  }

  void _onStarted() {
    final since = _clock();
    _since = since;
    _emit(TunnelStatus.connected(since: since, nodeId: _nodeId));
    // The tunnel is up; whether traffic actually flows is a separate question,
    // and answering it is what `checking` is for.
    _emit(TunnelStatus.checking(since: since, nodeId: _nodeId));
    _note(LogLevel.info, 'inbound/tun: started at 172.19.0.1/30');
    _ticker = Timer.periodic(_tick, (_) => _onTick());
    _checkTimer = Timer(_checkDelay, () {
      _emit(TunnelStatus.connected(since: since, nodeId: _nodeId));
      _note(LogLevel.info, 'reachability confirmed');
    });
  }

  void _onTick() {
    _ticks++;
    final uplink = 8 * 1024 + _next(120 * 1024);
    final downlink = 32 * 1024 + _next(900 * 1024);
    _uplinkTotal += uplink;
    _downlinkTotal += downlink;
    if (!_trafficController.isClosed) {
      _trafficController.add(
        TrafficSample(
          uplink: uplink,
          downlink: downlink,
          uplinkTotal: _uplinkTotal,
          downlinkTotal: _downlinkTotal,
          at: _clock(),
        ),
      );
    }
    _note(LogLevel.debug, _sampleMessages[_ticks % _sampleMessages.length]);
    if (!_connectionsController.isClosed) {
      _connectionsController.add(_snapshot());
    }
  }

  List<ConnectionInfo> _snapshot() {
    final now = _clock();
    final count = 1 + _ticks % _sampleHosts.length;
    return <ConnectionInfo>[
      for (var index = 0; index < count; index++)
        ConnectionInfo(
          id: 'fake-${_ticks - index}',
          host: _sampleHosts[index],
          rule: index.isEven
              ? 'geosite:private → direct'
              : 'default → ${SwitchNodeUseCase.defaultGroupTag}',
          outbound:
              index.isEven ? 'direct' : SwitchNodeUseCase.defaultGroupTag,
          uploadTotal: _uplinkTotal ~/ count,
          downloadTotal: _downlinkTotal ~/ count,
          start: now.subtract(Duration(seconds: index * 7 + 3)),
          network: index == 2 ? 'udp' : 'tcp',
        ),
    ];
  }

  /// Writes a synthetic *core* line to [logs] — and only there.
  ///
  /// The injected logger is for the client's own diagnostics, the same split
  /// `CoreClientFactory.create` promises and `AndroidCoreClient` keeps: the
  /// real core's log arrives through `logs` alone. Feeding both would make
  /// the app's log pump, which follows both, record every fake line twice.
  void _note(LogLevel level, String message) {
    if (_logsController.isClosed) {
      return;
    }
    _logsController.add(LogLine(level: level, message: message, at: _clock()));
  }

  void _emit(TunnelStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _guard(FakeCoreStep step, {bool resetsState = false}) {
    final failure = _failures[step];
    if (failure == null) {
      return;
    }
    if (resetsState) {
      _cancelTimers();
      _running = false;
      _since = null;
      _emit(TunnelStatus.error(failure));
    }
    throw CoreClientException(failure);
  }

  void _requireRunning() {
    if (!_running) {
      // The wire code is `not_running`; it maps onto the same failure the user
      // sees when the tunnel service is not there at all.
      throw const CoreClientException(HelperUnavailableFailure());
    }
  }

  void _cancelTimers() {
    _startTimer?.cancel();
    _checkTimer?.cancel();
    _stopTimer?.cancel();
    _ticker?.cancel();
    _startTimer = null;
    _checkTimer = null;
    _stopTimer = null;
    _ticker = null;
  }

  /// A linear congruential generator, so the traffic series is reproducible.
  int _next(int bound) {
    _random = (_random * 1103515245 + 12345) & 0x7FFFFFFF;
    return _random % bound;
  }

  static const List<String> _sampleHosts = <String>[
    'example.com:443',
    'cdn.example.org:443',
    'dns.example.net:53',
    'api.example.io:443',
  ];

  static const List<String> _sampleMessages = <String>[
    'router: found process path /usr/bin/curl',
    'dns: exchange example.com IN A',
    'outbound/direct: connection to 93.184.216.34:443',
    'router: match[7] geosite=ads => reject',
  ];
}
