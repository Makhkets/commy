import 'package:commy_core/src/wire/wire_failure_mapper.dart';
import 'package:commy_core/src/wire/wire_format_exception.dart';
import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_core/src/wire/wire_states.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `/status` events.
///
/// This is the boundary the raw protocol stops at: above it there are only the
/// six `TunnelStatus` variants, and the UI is forced by the compiler to handle
/// all six.
abstract final class TunnelStatusCodec {
  /// Decodes one `/status` event.
  ///
  /// [fallbackSince] is used when the core reported `connected` or `checking`
  /// without a timestamp: the timer on screen has to start somewhere, and
  /// "now" is closer to the truth than the epoch.
  static TunnelStatus decode(Object? raw, {DateTime? fallbackSince}) {
    final json = WireJson.object(raw, '/status event');
    final state = WireJson.stringOr(
      json,
      WireKeys.state,
      orElse: WireStates.idle,
    );
    final nodeId = WireJson.stringOrNull(json, WireKeys.nodeId);
    final since = WireJson.epochMillisOrNull(json, WireKeys.since) ??
        fallbackSince ??
        DateTime.now();

    switch (state) {
      case WireStates.idle:
        return const TunnelStatus.idle();
      case WireStates.starting:
        return const TunnelStatus.starting();
      case WireStates.connected:
        return TunnelStatus.connected(since: since, nodeId: nodeId);
      case WireStates.checking:
        return TunnelStatus.checking(since: since, nodeId: nodeId);
      case WireStates.stopping:
        return const TunnelStatus.stopping();
      case WireStates.error:
        return TunnelStatus.error(_failure(json));
    }

    throw WireFormatException('/status event', 'unknown state "$state"');
  }

  /// Encodes [status] back into the wire shape.
  ///
  /// Used by `FakeCoreClient` and by the contract tests, which drive a real
  /// decoder with synthetic events instead of asserting on hand-built objects.
  static JsonMap encode(TunnelStatus status) => switch (status) {
        TunnelIdle() => <String, Object?>{WireKeys.state: WireStates.idle},
        TunnelStarting() => <String, Object?>{
            WireKeys.state: WireStates.starting,
          },
        TunnelConnected(:final since, :final nodeId) => <String, Object?>{
            WireKeys.state: WireStates.connected,
            WireKeys.since: since.toUtc().millisecondsSinceEpoch,
            WireKeys.nodeId: nodeId,
          },
        TunnelChecking(:final since, :final nodeId) => <String, Object?>{
            WireKeys.state: WireStates.checking,
            WireKeys.since: since.toUtc().millisecondsSinceEpoch,
            WireKeys.nodeId: nodeId,
          },
        TunnelStopping() => <String, Object?>{
            WireKeys.state: WireStates.stopping,
          },
        TunnelError(:final failure) => <String, Object?>{
            WireKeys.state: WireStates.error,
            WireKeys.code: failure.code,
            WireKeys.reason: _reasonOf(failure),
          },
      };

  static CommyFailure _failure(JsonMap json) {
    final code = WireJson.stringOr(
      json,
      WireKeys.code,
      orElse: 'unknown',
    );
    final reason = WireJson.stringOrNull(json, WireKeys.reason);
    // `already_running` maps to "no failure", which cannot happen on a status
    // event: the state field already said `error`. Fall back rather than
    // silently pretend the tunnel is fine.
    return WireFailureMapper.fromCode(code, message: reason) ??
        UnknownFailure(reason ?? code, StackTrace.empty);
  }

  static String _reasonOf(CommyFailure failure) {
    switch (failure) {
      case CoreCrashedFailure(:final log):
        return log;
      case ConfigInvalidFailure(:final detail):
        return detail;
      case StorageFailure(:final cause):
        return '$cause';
      case UnknownFailure(:final cause):
        return '$cause';
      case SubscriptionMalformedFailure(:final detail):
        return detail;
      case UnsupportedProtocolFailure(:final scheme):
        return scheme;
      case SubscriptionUnreachableFailure(:final url):
        return Redact.uri(url);
      case PermissionDeniedFailure():
      case HelperUnavailableFailure():
        return '';
    }
  }
}
