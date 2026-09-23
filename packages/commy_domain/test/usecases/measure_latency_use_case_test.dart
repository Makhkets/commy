import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/subscription_fakes.dart';

const ProxyNode _reality = ProxyNode(
  id: 'cz',
  name: 'Czech Republic',
  protocol: Protocol.vless,
  host: '45.151.180.167',
  port: 8443,
  params: <String, Object?>{'security': 'reality'},
);

const ProxyNode _hysteria = ProxyNode(
  id: 'fi',
  name: 'Finland',
  protocol: Protocol.hysteria2,
  host: 'fi.example',
  port: 443,
);

/// The "Ping" setting decides how a server is timed, and nothing else does:
/// not whether the tunnel is up, not what the last method was.
void main() {
  late _Settings settings;
  late _Routing routing;
  late _Generator generator;
  late _Core core;
  late _Probe probe;
  late _Nodes nodes;
  late MeasureLatencyUseCase measure;

  setUp(() {
    settings = _Settings();
    routing = _Routing();
    generator = _Generator();
    core = _Core();
    probe = _Probe();
    nodes = _Nodes();
    measure = MeasureLatencyUseCase(
      core: core,
      probe: probe,
      nodes: nodes,
      settings: settings,
      routing: routing,
      generator: generator,
    );
  });

  test('GET is the default, and goes through the server by a probe core',
      () async {
    core.delays = <String, Duration?>{
      'node-cz': const Duration(milliseconds: 212),
    };

    final result = await measure(node: _reality, outboundTag: 'node-cz');

    expect(result.valueOrNull, const Duration(milliseconds: 212));
    expect(generator.nodes, <ProxyNode>[_reality]);
    expect(generator.dns, routing.dns, reason: 'resolved like the tunnel');
    expect(core.probe, Uri.parse(AppSettings.defaultLatencyProbeUrl));
    expect(core.timeout, MeasureLatencyUseCase.proxyTimeout);
    expect(probe.asked, isEmpty, reason: 'no TCP handshake, no echo');
    expect(nodes.latencies, <String, Duration?>{
      'cz': const Duration(milliseconds: 212),
    });
  });

  test('a server that did not answer the GET is a measurement of nothing',
      () async {
    core.delays = <String, Duration?>{'node-cz': null};

    final result = await measure(node: _reality, outboundTag: 'node-cz');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isNull);
    expect(nodes.latencies, containsPair('cz', null));
  });

  test('GET times a UDP server too: the probe core speaks its protocol',
      () async {
    core.delays = <String, Duration?>{
      'node-fi': const Duration(milliseconds: 90),
    };

    final result = await measure(node: _hysteria, outboundTag: 'node-fi');

    expect(result.valueOrNull, const Duration(milliseconds: 90));
    expect(MeasureLatencyUseCase.canMeasure(_hysteria, PingMethod.get), isTrue);
  });

  test('GET without a probe URL is a failure to report, not a dash', () async {
    settings.value = const AppSettings(latencyProbeUrl: '');

    final result = await measure(node: _reality, outboundTag: 'node-cz');

    expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    expect(core.probe, isNull);
  });

  test('TCP times the handshake directly', () async {
    settings.value = const AppSettings(pingMethod: PingMethod.tcp);

    final result = await measure(node: _reality, outboundTag: 'node-cz');

    expect(result.valueOrNull, _Probe.answer);
    expect(probe.asked, <String>['tcp 45.151.180.167:8443']);
    expect(core.probe, isNull, reason: 'no core for a handshake');
  });

  test('TCP refuses a server that has no TCP port', () async {
    settings.value = const AppSettings(pingMethod: PingMethod.tcp);

    final result = await measure(node: _hysteria, outboundTag: 'node-fi');

    expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    expect(probe.asked, isEmpty);
    expect(
      MeasureLatencyUseCase.canMeasure(_hysteria, PingMethod.tcp),
      isFalse,
    );
  });

  test('ICMP sends an echo to the host', () async {
    settings.value = const AppSettings(pingMethod: PingMethod.icmp);

    final result = await measure(node: _hysteria, outboundTag: 'node-fi');

    expect(result.valueOrNull, _Probe.answer);
    expect(probe.asked, <String>['icmp fi.example']);
  });
}

class _Settings implements SettingsRepository {
  AppSettings value = AppSettings.defaults;

  @override
  Future<Result<AppSettings, CommyFailure>> read() async =>
      Ok<AppSettings, CommyFailure>(value);

  @override
  Future<Result<void, CommyFailure>> write(AppSettings settings) async {
    value = settings;
    return const Ok<void, CommyFailure>(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Routing implements RoutingRepository {
  final DnsSettings dns = const DnsSettings(direct: 'udp://77.88.8.8');

  @override
  Future<Result<DnsSettings, CommyFailure>> readDns() async =>
      Ok<DnsSettings, CommyFailure>(dns);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Generator implements ConfigGenerator {
  List<ProxyNode>? nodes;
  DnsSettings? dns;

  @override
  Result<CoreConfig, CommyFailure> buildProbe({
    required List<ProxyNode> nodes,
    required DnsSettings dns,
  }) {
    this.nodes = nodes;
    this.dns = dns;
    return const Ok<CoreConfig, CommyFailure>(
      CoreConfig(<String, Object?>{'outbounds': <Object?>[]}),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Core implements CoreClient {
  Map<String, Duration?> delays = const <String, Duration?>{};
  Uri? probe;
  Duration? timeout;

  @override
  Future<Map<String, Duration?>> probeOutbounds(
    CoreConfig config, {
    required Uri probe,
    required Duration timeout,
  }) async {
    this.probe = probe;
    this.timeout = timeout;
    return delays;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Probe implements LatencyProbe {
  static const Duration answer = Duration(milliseconds: 41);

  final List<String> asked = <String>[];

  @override
  Future<Duration?> connectTime(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    asked.add('tcp $host:$port');
    return answer;
  }

  @override
  Future<Duration?> echoTime(String host, {required Duration timeout}) async {
    asked.add('icmp $host');
    return answer;
  }
}

class _Nodes extends RecordingNodeRepository {
  final Map<String, Duration?> latencies = <String, Duration?>{};

  @override
  Future<Result<void, CommyFailure>> updateLatency({
    required String id,
    required Duration? latency,
    required DateTime checkedAt,
  }) async {
    latencies[id] = latency;
    return const Ok<void, CommyFailure>(null);
  }
}
