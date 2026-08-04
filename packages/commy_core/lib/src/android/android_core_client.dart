import 'dart:async';

import 'package:commy_core/src/core_client_exception.dart';
import 'package:commy_core/src/logging/app_logger.dart';
import 'package:commy_core/src/wire/connection_info_codec.dart';
import 'package:commy_core/src/wire/log_line_codec.dart';
import 'package:commy_core/src/wire/proxy_group_codec.dart';
import 'package:commy_core/src/wire/select_codec.dart';
import 'package:commy_core/src/wire/traffic_sample_codec.dart';
import 'package:commy_core/src/wire/tunnel_status_codec.dart';
import 'package:commy_core/src/wire/url_test_codec.dart';
import 'package:commy_core/src/wire/wire_channels.dart';
import 'package:commy_core/src/wire/wire_failure_mapper.dart';
import 'package:commy_core/src/wire/wire_format_exception.dart';
import 'package:commy_core/src/wire/wire_methods.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/services.dart';

/// The `CoreClient` that talks to the Android tunnel service.
///
/// One `MethodChannel` down, four `EventChannel`s up, every payload a JSON
/// string. The whole contract with Kotlin is in
/// `packages/commy_core/docs/wire-protocol.md`; the constants it is built from
/// live in `lib/src/wire/`, so a rename shows up as a compile error on this
/// side and as a single diff on the other.
///
/// On Android the core runs *inside this process*, under `VpnService`, and the
/// return path is libbox's own `CommandClient`. The Clash API is not involved
/// and must not be — an HTTP server inside the tunnel process is memory we do
/// not have and attack surface we do not need (ADR-0005).
///
/// ## Failures stay typed
///
/// Every platform error is mapped through [WireFailureMapper] and re-thrown as
/// a [CoreClientException] carrying a `CommyFailure`. `permission_denied` in
/// particular has to survive all the way to a screen: "the user declined the
/// VPN dialog and the app said nothing" is a named acceptance failure
/// (docs/07-roadmap.md, M1 criterion 4).
///
/// `already_running` is not an error. The caller asked for a tunnel and there
/// is one, so the call succeeded; the user sees nothing.
class AndroidCoreClient implements CoreClient {
  /// Creates the client.
  ///
  /// [logger] receives the client's own diagnostics — malformed payloads,
  /// swallowed `already_running`, channel errors. It is *not* where the core
  /// log goes: that is the [logs] stream, which the composition root wires into
  /// the log repository.
  ///
  /// [groupTag] is the outbound group `select` and `urlTest` address. It
  /// matches `SingBoxConfigBuilder`, which names the group `proxy`.
  AndroidCoreClient({
    AppLogger? logger,
    Duration urlTestTimeout = UrlTestCodec.defaultTimeout,
    String groupTag = SwitchNodeUseCase.defaultGroupTag,
  })  : _logger = logger,
        _urlTestTimeout = urlTestTimeout,
        _groupTag = groupTag;

  /// Tag the client's own log lines carry.
  static const String logTag = 'core.android';

  static const MethodChannel _method = MethodChannel(WireChannels.method);
  static const EventChannel _statusChannel =
      EventChannel(WireChannels.status);
  static const EventChannel _trafficChannel =
      EventChannel(WireChannels.traffic);
  static const EventChannel _logsChannel = EventChannel(WireChannels.logs);
  static const EventChannel _connectionsChannel =
      EventChannel(WireChannels.connections);

  final AppLogger? _logger;
  final Duration _urlTestTimeout;
  final String _groupTag;

  /// Kept so `since` is not recomputed on a status event that omits it: the
  /// on-screen timer hangs off that value and must not jump.
  DateTime? _since;

  late final Stream<TunnelStatus> _status = _events<TunnelStatus>(
    channel: _statusChannel,
    what: WireChannels.status,
    decode: (raw) => <TunnelStatus>[_decodeStatus(raw)],
    onError: _statusError,
  );

  late final Stream<TrafficSample> _traffic = _events<TrafficSample>(
    channel: _trafficChannel,
    what: WireChannels.traffic,
    decode: (raw) => <TrafficSample>[TrafficSampleCodec.decode(raw)],
  );

  late final Stream<LogLine> _logs = _events<LogLine>(
    channel: _logsChannel,
    what: WireChannels.logs,
    decode: LogLineCodec.decodeList,
  );

  late final Stream<List<ConnectionInfo>> _connections =
      _events<List<ConnectionInfo>>(
    channel: _connectionsChannel,
    what: WireChannels.connections,
    decode: (raw) => <List<ConnectionInfo>>[
      ConnectionInfoCodec.decodeList(raw),
    ],
  );

  @override
  Stream<TunnelStatus> get status => _status;

  @override
  Stream<TrafficSample> get traffic => _traffic;

  @override
  Stream<LogLine> get logs => _logs;

  @override
  Stream<List<ConnectionInfo>> get connections => _connections;

  @override
  Future<void> start(CoreConfig config) async {
    await _invoke(WireMethods.start, config.encode());
  }

  @override
  Future<void> stop() async {
    await _invoke(WireMethods.stop);
  }

  @override
  Future<void> reload(CoreConfig config) async {
    await _invoke(WireMethods.reload, config.encode());
  }

  @override
  Future<void> select(String group, String tag) async {
    await _invoke(
      WireMethods.select,
      SelectCodec.encodeRequest(group: group, tag: tag),
    );
  }

  @override
  Future<Duration?> urlTest(String tag, Uri probe) async {
    final raw = await _invoke(
      WireMethods.urlTest,
      UrlTestCodec.encodeRequest(
        tag: tag,
        probe: probe,
        group: _groupTag,
        timeout: _urlTestTimeout,
      ),
    );
    return _read(WireMethods.urlTest, () => UrlTestCodec.decodeDelay(raw));
  }

  @override
  Future<List<ProxyGroup>> proxies() async {
    final raw = await _invoke(WireMethods.proxies);
    return _read(
      WireMethods.proxies,
      () => ProxyGroupCodec.decodeList(raw),
    );
  }

  /// The sing-box version string, for the about screen.
  ///
  /// Not part of [CoreClient]: the domain has no reason to know which core it
  /// is riding on, and only one screen does.
  Future<String> version() async {
    final raw = await _invoke(WireMethods.version);
    return raw == null ? '' : '$raw';
  }

  Future<Object?> _invoke(String method, [Object? argument]) async {
    try {
      return await _method.invokeMethod<Object?>(method, argument);
    } on Object catch (error, stackTrace) {
      final failure = WireFailureMapper.fromError(error, stackTrace);
      if (failure == null) {
        // `already_running`: the tunnel the caller wanted is already up.
        _logger?.debug('$method: already running', tag: logTag);
        return null;
      }
      _logger?.warn('$method failed: ${failure.code}', tag: logTag);
      throw CoreClientException(
        failure,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Runs a decoder over a method *result*.
  ///
  /// A malformed event is dropped; a malformed result is a failure, because
  /// somebody is waiting on this future and silence is the one answer they
  /// cannot handle.
  T _read<T>(String method, T Function() decode) {
    try {
      return decode();
    } on WireFormatException catch (error, stackTrace) {
      _logger?.error('$method: bad result', tag: logTag, error: error);
      throw CoreClientException(
        UnknownFailure(error, stackTrace),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  TunnelStatus _decodeStatus(Object? raw) {
    final status = TunnelStatusCodec.decode(raw, fallbackSince: _since);
    _since = switch (status) {
      TunnelConnected(:final since) => since,
      TunnelChecking(:final since) => since,
      TunnelIdle() ||
      TunnelStarting() ||
      TunnelStopping() ||
      TunnelError() =>
        null,
    };
    return status;
  }

  /// Turns an error on `/status` into an `error` state rather than a stream
  /// error.
  ///
  /// The status stream is what the connect button is bound to. An error event
  /// delivered as a stream error would be swallowed by whatever `onError` the
  /// screen happens to have, and the button would sit in `connecting` forever.
  /// As a state it is impossible to miss: the compiler makes every screen
  /// handle [TunnelError].
  void _statusError(
    CommyFailure failure,
    EventSink<TunnelStatus> sink,
  ) =>
      sink.add(TunnelStatus.error(failure));

  /// Wires one `EventChannel` into a typed broadcast stream.
  ///
  /// A payload that does not parse is logged and dropped: one bad log line must
  /// not tear down the subscription that carries the tunnel state.
  Stream<T> _events<T>({
    required EventChannel channel,
    required String what,
    required List<T> Function(Object? raw) decode,
    void Function(CommyFailure failure, EventSink<T> sink)? onError,
  }) {
    return channel.receiveBroadcastStream().transform(
          StreamTransformer<Object?, T>.fromHandlers(
            handleData: (raw, sink) {
              try {
                decode(raw).forEach(sink.add);
              } on WireFormatException catch (error) {
                _logger?.warn(
                  '$what: dropped a malformed payload',
                  tag: logTag,
                  error: error,
                );
              }
            },
            handleError: (error, stackTrace, sink) {
              final failure =
                  WireFailureMapper.fromError(error, stackTrace) ??
                      const HelperUnavailableFailure();
              _logger?.warn('$what: ${failure.code}', tag: logTag);
              if (onError != null) {
                onError(failure, sink);
                return;
              }
              sink.addError(
                CoreClientException(
                  failure,
                  cause: error,
                  stackTrace: stackTrace,
                ),
                stackTrace,
              );
            },
          ),
        );
  }
}
