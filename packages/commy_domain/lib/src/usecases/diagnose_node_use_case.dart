import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/dns_settings.dart';
import 'package:commy_domain/src/entities/protocol.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/ports/config_generator.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/latency_probe.dart';
import 'package:commy_domain/src/ports/network_diagnostics.dart';
import 'package:commy_domain/src/ports/routing_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';
import 'package:commy_domain/src/usecases/measure_latency_use_case.dart';

/// One check of a diagnosis, in the order they run.
enum DiagnosisStep {
  /// The server's name resolves to an address.
  dns,

  /// Its TCP port accepts a connection.
  tcp,

  /// A TLS handshake with its server name completes.
  tls,

  /// A request goes through the server, by its own protocol.
  proxy,
}

/// How one check came out.
enum StepStatus {
  /// Not run yet.
  pending,

  /// It worked.
  passed,

  /// It did not.
  failed,

  /// It does not apply to this server: an IP needs no DNS, a UDP server has
  /// no TCP port, a server without TLS has no handshake to check.
  skipped,
}

/// What a diagnosis concludes — the one sentence the user reads.
enum DiagnosisVerdict {
  /// Still running.
  running,

  /// A request went through: the server works from here.
  works,

  /// The name does not resolve — a typo, an expired domain, or DNS that is
  /// filtered on this network.
  dnsFailed,

  /// The port does not accept connections — the server is down, or this
  /// network or the server's firewall blocks it.
  portClosed,

  /// The TLS handshake failed — blocked by its name (SNI), or the server's
  /// TLS is broken.
  tlsFailed,

  /// The certificate was refused — expired, for another name, or the phone's
  /// clock is wrong.
  certificateRefused,

  /// Everything up to the protocol works and the protocol does not: a key or
  /// UUID that is no longer valid, a subscription that ran out, or the
  /// protocol itself filtered.
  protocolRefused,

  /// The network checks passed; the protocol check is off ("Ping" has no
  /// probe address), so this is as far as it can see.
  reachable,
}

/// One check and what it found.
class DiagnosisResult {
  /// Creates the result.
  const DiagnosisResult(this.step, this.status, {this.detail});

  /// Which check.
  final DiagnosisStep step;

  /// How it went.
  final StepStatus status;

  /// An address, a round trip in milliseconds, a reason — for the screen.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosisResult &&
          other.step == step &&
          other.status == status &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(step, status, detail);

  @override
  String toString() => 'DiagnosisResult(${step.name}: ${status.name})';
}

/// A diagnosis, finished or on its way.
class NodeDiagnosis {
  /// Creates the diagnosis.
  const NodeDiagnosis({required this.steps, required this.verdict});

  /// Every step, pending ones included, in order.
  final List<DiagnosisResult> steps;

  /// What it concludes; [DiagnosisVerdict.running] until it does.
  final DiagnosisVerdict verdict;

  /// Whether it is done.
  bool get isDone => verdict != DiagnosisVerdict.running;

  @override
  String toString() => 'NodeDiagnosis(${verdict.name})';
}

/// "Why does it not connect?" — the server checked one layer at a time,
/// so the answer names the layer that broke (docs/19-commy-cloud.md, §3.1).
///
/// Happ and INCY answer this with a wizard; Commy used to answer it with a
/// log. Four checks, each only where it applies, stopping at the first that
/// fails — what lies above a broken layer cannot be judged:
///
/// 1. **DNS** — the server's name resolves (skipped for an IP);
/// 2. **TCP** — its port accepts a connection (skipped for UDP servers:
///    Hysteria2, TUIC, WireGuard, QUIC and HTTP/3 transports);
/// 3. **TLS** — a handshake with the server's SNI completes; for REALITY a
///    completed handshake is the camouflage answering, so the certificate
///    is not judged (skipped without TLS);
/// 4. **Protocol** — a GET through the server, by a core instance of its own,
///    as the GET ping does.
///
/// Every request goes to the user's server and nowhere else, around the
/// tunnel — exactly where the connect would go (rule R1 has nothing to add).
class DiagnoseNodeUseCase {
  /// Creates the use case.
  const DiagnoseNodeUseCase({
    required this.network,
    required this.probe,
    required this.core,
    required this.settings,
    required this.routing,
    required this.generator,
  });

  /// Name resolution and the TLS handshake.
  final NetworkDiagnostics network;

  /// The TCP handshake.
  final LatencyProbe probe;

  /// The request through the server.
  final CoreClient core;

  /// Where the probe address comes from.
  final SettingsRepository settings;

  /// Where DNS for the probe instance comes from.
  final RoutingRepository routing;

  /// What builds the probe instance's document.
  final ConfigGenerator generator;

  /// How long each network check is waited for.
  static const Duration stepTimeout = Duration(seconds: 6);

  /// How long the request through the server is waited for.
  static const Duration proxyTimeout = Duration(seconds: 10);

  /// The steps that apply to [node], in order.
  static List<DiagnosisStep> stepsFor(ProxyNode node) => <DiagnosisStep>[
        if (!_isAddress(node.host)) DiagnosisStep.dns,
        if (MeasureLatencyUseCase.acceptsTcp(node)) DiagnosisStep.tcp,
        if (MeasureLatencyUseCase.acceptsTcp(node) && _tlsOf(node) != null)
          DiagnosisStep.tls,
        DiagnosisStep.proxy,
      ];

  /// Runs the checks on [node]; [onProgress] hears every step as it ends.
  Future<NodeDiagnosis> call(
    ProxyNode node, {
    void Function(NodeDiagnosis progress)? onProgress,
  }) async {
    final order = stepsFor(node);
    final results = <DiagnosisStep, DiagnosisResult>{
      for (final step in DiagnosisStep.values)
        step: DiagnosisResult(
          step,
          order.contains(step) ? StepStatus.pending : StepStatus.skipped,
        ),
    };
    NodeDiagnosis snapshot(DiagnosisVerdict verdict) => NodeDiagnosis(
          steps: <DiagnosisResult>[
            for (final step in DiagnosisStep.values) results[step]!,
          ],
          verdict: verdict,
        );
    NodeDiagnosis finish(DiagnosisVerdict verdict) {
      final done = snapshot(verdict);
      onProgress?.call(done);
      return done;
    }

    void record(DiagnosisResult result) {
      results[result.step] = result;
      onProgress?.call(snapshot(DiagnosisVerdict.running));
    }

    onProgress?.call(snapshot(DiagnosisVerdict.running));

    if (order.contains(DiagnosisStep.dns)) {
      final addresses = await network.resolve(node.host, timeout: stepTimeout);
      if (addresses == null || addresses.isEmpty) {
        record(const DiagnosisResult(DiagnosisStep.dns, StepStatus.failed));
        return finish(DiagnosisVerdict.dnsFailed);
      }
      record(
        DiagnosisResult(
          DiagnosisStep.dns,
          StepStatus.passed,
          detail: addresses.first,
        ),
      );
    }

    if (order.contains(DiagnosisStep.tcp)) {
      final connected = await probe.connectTime(
        node.host,
        node.port,
        timeout: stepTimeout,
      );
      if (connected == null) {
        record(const DiagnosisResult(DiagnosisStep.tcp, StepStatus.failed));
        return finish(DiagnosisVerdict.portClosed);
      }
      record(
        DiagnosisResult(
          DiagnosisStep.tcp,
          StepStatus.passed,
          detail: '${connected.inMilliseconds}',
        ),
      );
    }

    if (order.contains(DiagnosisStep.tls)) {
      final tls = _tlsOf(node)!;
      final outcome = await network.tlsHandshake(
        node.host,
        node.port,
        serverName: tls.serverName,
        timeout: stepTimeout,
      );
      final certificateMatters = !tls.reality && !tls.insecure;
      switch (outcome) {
        case TlsOutcome.completed:
          record(
            DiagnosisResult(
              DiagnosisStep.tls,
              StepStatus.passed,
              detail: tls.serverName,
            ),
          );
        case TlsOutcome.badCertificate when !certificateMatters:
          record(
            DiagnosisResult(
              DiagnosisStep.tls,
              StepStatus.passed,
              detail: tls.serverName,
            ),
          );
        case TlsOutcome.badCertificate:
          record(
            DiagnosisResult(
              DiagnosisStep.tls,
              StepStatus.failed,
              detail: tls.serverName,
            ),
          );
          return finish(DiagnosisVerdict.certificateRefused);
        case TlsOutcome.failed:
          record(
            DiagnosisResult(
              DiagnosisStep.tls,
              StepStatus.failed,
              detail: tls.serverName,
            ),
          );
          return finish(DiagnosisVerdict.tlsFailed);
      }
    }

    final through = await _throughServer(node);
    switch (through) {
      case _Through(skipped: true):
        record(const DiagnosisResult(DiagnosisStep.proxy, StepStatus.skipped));
        return finish(DiagnosisVerdict.reachable);
      case _Through(:final latency?):
        record(
          DiagnosisResult(
            DiagnosisStep.proxy,
            StepStatus.passed,
            detail: '${latency.inMilliseconds}',
          ),
        );
        return finish(DiagnosisVerdict.works);
      case _Through():
        record(const DiagnosisResult(DiagnosisStep.proxy, StepStatus.failed));
        return finish(DiagnosisVerdict.protocolRefused);
    }
  }

  Future<_Through> _throughServer(ProxyNode node) async {
    final appSettings =
        (await settings.read()).valueOrNull ?? AppSettings.defaults;
    final url = Uri.tryParse(appSettings.latencyProbeUrl);
    if (!appSettings.isLatencyProbeEnabled || url == null) {
      return const _Through(null, skipped: true);
    }
    final dns = (await routing.readDns()).valueOrNull ?? DnsSettings.defaults;
    final built = generator.buildProbe(nodes: <ProxyNode>[node], dns: dns);
    final config = built.valueOrNull;
    if (config == null) {
      return const _Through(null);
    }
    try {
      final delays = await core.probeOutbounds(
        config,
        probe: url,
        timeout: proxyTimeout,
      );
      final values = delays.values.whereType<Duration>();
      return _Through(values.isEmpty ? null : values.first);
    } on Object {
      return const _Through(null);
    }
  }

  /// The TLS a handshake can check, or `null` when the server has none on
  /// TCP. Trojan is TLS by definition; the rest say so in `security`.
  static ({String serverName, bool reality, bool insecure})? _tlsOf(
    ProxyNode node,
  ) {
    final security = node.param('security')?.trim().toLowerCase();
    final tls = security == 'tls' ||
        security == 'reality' ||
        (node.protocol == Protocol.trojan && security != 'none');
    if (!tls) {
      return null;
    }
    final name = <String?>[
      node.param('sni'),
      node.param('peer'),
      node.param('servername'),
    ].firstWhere(
      (value) => value != null && value.trim().isNotEmpty,
      orElse: () => node.host,
    )!;
    final insecure = <String?>[
      node.param('allowInsecure'),
      node.param('insecure'),
    ].any((value) => value == '1' || value?.toLowerCase() == 'true');
    return (
      serverName: name.trim(),
      reality: security == 'reality',
      insecure: insecure,
    );
  }

  static bool _isAddress(String host) =>
      _ipv4.hasMatch(host) || host.contains(':');

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
}

class _Through {
  const _Through(this.latency, {this.skipped = false});

  final Duration? latency;

  final bool skipped;
}
