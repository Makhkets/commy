import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `/traffic` events.
///
/// The counters are 64-bit and cross the boundary as JSON numbers rather than
/// through `StandardMessageCodec`, which rounds anything past 2^31 differently
/// on different platforms — a gigabyte of traffic is enough to hit that
/// (`docs/wire-protocol.md`, "Каналы").
abstract final class TrafficSampleCodec {
  /// Decodes one `/traffic` event.
  ///
  /// [fallbackAt] stands in when the native side omitted `at`, which the
  /// protocol allows. Every field defaults to zero: a tick with a missing
  /// counter is still a usable tick, and dropping it would leave a hole in the
  /// chart for no gain.
  static TrafficSample decode(Object? raw, {DateTime? fallbackAt}) {
    final json = WireJson.object(raw, '/traffic event');
    return TrafficSample(
      uplink: WireJson.integerOr(json, WireKeys.up, orElse: 0),
      downlink: WireJson.integerOr(json, WireKeys.down, orElse: 0),
      uplinkTotal: WireJson.integerOr(json, WireKeys.upTotal, orElse: 0),
      downlinkTotal: WireJson.integerOr(json, WireKeys.downTotal, orElse: 0),
      at: WireJson.epochMillisOr(
        json,
        WireKeys.at,
        orElse: fallbackAt ?? DateTime.now(),
      ),
    );
  }

  /// Encodes [sample] back into the wire shape.
  static JsonMap encode(TrafficSample sample) => <String, Object?>{
        WireKeys.up: sample.uplink,
        WireKeys.down: sample.downlink,
        WireKeys.upTotal: sample.uplinkTotal,
        WireKeys.downTotal: sample.downlinkTotal,
        WireKeys.at: sample.at.toUtc().millisecondsSinceEpoch,
      };
}
