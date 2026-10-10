import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/backup_fakes.dart';

/// "Why does it not connect?" — each layer checked in turn, the first one
/// that breaks named.
void main() {
  const vlessReality = ProxyNode(
    id: 'n1',
    name: 'Amsterdam',
    protocol: Protocol.vless,
    host: 'nl.example.net',
    port: 443,
    params: <String, Object?>{
      'security': 'reality',
      'sni': 'www.microsoft.com',
      'type': 'tcp',
    },
  );

  late _Network network;
  late _Probe probe;
  late _Core core;

  DiagnoseNodeUseCase useCase() => DiagnoseNodeUseCase(
        network: network,
        probe: probe,
        core: core,
        settings: MemorySettingsRepository(),
        routing: MemoryRoutingRepository(),
        generator: _Generator(),
      );

  setUp(() {
    network = _Network();
    probe = _Probe();
    core = _Core();
  });

  StepStatus statusOf(NodeDiagnosis diagnosis, DiagnosisStep step) =>
      diagnosis.steps.firstWhere((result) => result.step == step).status;

  test('a working server passes every layer', () async {
    final progress = <DiagnosisVerdict>[];

    final diagnosis = await useCase()(
      vlessReality,
      onProgress: (p) => progress.add(p.verdict),
    );

    expect(diagnosis.verdict, DiagnosisVerdict.works);
    for (final step in DiagnosisStep.values) {
      expect(statusOf(diagnosis, step), StepStatus.passed, reason: '$step');
    }
    expect(progress.first, DiagnosisVerdict.running);
    expect(progress.last, DiagnosisVerdict.works);
    expect(network.serverNames, <String>['www.microsoft.com']);
  });

  test('a name that does not resolve stops there', () async {
    network.addresses = null;

    final diagnosis = await useCase()(vlessReality);

    expect(diagnosis.verdict, DiagnosisVerdict.dnsFailed);
    expect(statusOf(diagnosis, DiagnosisStep.tcp), StepStatus.pending);
    expect(probe.calls, 0);
  });

  test('a closed port is named as such', () async {
    probe.latency = null;

    expect(
      (await useCase()(vlessReality)).verdict,
      DiagnosisVerdict.portClosed,
    );
  });

  test("REALITY's camouflage certificate is not judged, a TLS one is",
      () async {
    network.outcome = TlsOutcome.badCertificate;

    expect((await useCase()(vlessReality)).verdict, DiagnosisVerdict.works);

    final tls = vlessReality.copyWith(
      params: <String, Object?>{'security': 'tls', 'sni': 'nl.example.net'},
    );
    expect(
      (await useCase()(tls)).verdict,
      DiagnosisVerdict.certificateRefused,
    );
    final insecure = tls.copyWith(
      params: <String, Object?>{...tls.params, 'allowInsecure': '1'},
    );
    expect((await useCase()(insecure)).verdict, DiagnosisVerdict.works);
  });

  test('every layer but the protocol works: the key, the plan or DPI',
      () async {
    core.latency = null;

    final diagnosis = await useCase()(vlessReality);

    expect(diagnosis.verdict, DiagnosisVerdict.protocolRefused);
    expect(statusOf(diagnosis, DiagnosisStep.tls), StepStatus.passed);
  });

  test('a UDP server and an IP skip what does not apply', () async {
    const hysteria = ProxyNode(
      id: 'h1',
      name: 'Helsinki',
      protocol: Protocol.hysteria2,
      host: '203.0.113.5',
      port: 443,
    );

    final diagnosis = await useCase()(hysteria);

    expect(DiagnoseNodeUseCase.stepsFor(hysteria), <DiagnosisStep>[
      DiagnosisStep.proxy,
    ]);
    expect(statusOf(diagnosis, DiagnosisStep.dns), StepStatus.skipped);
    expect(statusOf(diagnosis, DiagnosisStep.tcp), StepStatus.skipped);
    expect(diagnosis.verdict, DiagnosisVerdict.works);
    expect(probe.calls, 0);
  });
}

class _Network implements NetworkDiagnostics {
  List<String>? addresses = <String>['198.51.100.7'];
  TlsOutcome outcome = TlsOutcome.completed;
  final List<String> serverNames = <String>[];

  @override
  Future<List<String>?> resolve(
    String host, {
    required Duration timeout,
  }) async =>
      addresses;

  @override
  Future<TlsOutcome> tlsHandshake(
    String host,
    int port, {
    required String serverName,
    required Duration timeout,
  }) async {
    serverNames.add(serverName);
    return outcome;
  }
}

class _Probe implements LatencyProbe {
  Duration? latency = const Duration(milliseconds: 40);
  int calls = 0;

  @override
  Future<Duration?> connectTime(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    calls++;
    return latency;
  }

  @override
  Future<Duration?> echoTime(String host, {required Duration timeout}) async =>
      null;
}

class _Core implements CoreClient {
  Duration? latency = const Duration(milliseconds: 120);

  @override
  Future<Map<String, Duration?>> probeOutbounds(
    CoreConfig config, {
    required Uri probe,
    required Duration timeout,
  }) async =>
      <String, Duration?>{'out': latency};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Generator implements ConfigGenerator {
  @override
  Result<CoreConfig, CommyFailure> buildProbe({
    required List<ProxyNode> nodes,
    required DnsSettings dns,
  }) =>
      const Ok<CoreConfig, CommyFailure>(CoreConfig(<String, Object?>{}));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
