import 'package:commy_core/src/wire/system_intent.dart';
import 'package:commy_core/src/wire/wire_channels.dart';
import 'package:flutter/services.dart';

/// The stream of things Android handed the app.
///
/// Separate from `CoreClient` on purpose: that port is the tunnel and is
/// implemented five times over, while this exists only where an operating
/// system has intents. Everywhere else it is simply an empty stream, which is
/// what lets the composition root wire it unconditionally.
///
/// The native side replays the last event, so a link that started the app is
/// still waiting when the Flutter engine finishes booting and subscribes. The
/// cost is that a hot restart re-delivers it, so whoever consumes this has to
/// be idempotent — which an import has to be anyway, for a link tapped twice.
class SystemIntents {
  /// Creates the source over the intents channel.
  const SystemIntents({EventChannel? channel})
      : _channel = channel ?? const EventChannel(WireChannels.intents);

  final EventChannel _channel;

  /// Events, with anything unreadable dropped rather than thrown.
  ///
  /// A malformed payload must not tear down the subscription: this stream is
  /// the app's front door for deep links, and a single bad event closing it
  /// would silently disable every later one.
  Stream<SystemIntent> get events => _channel
      .receiveBroadcastStream()
      .map((raw) => raw is String ? SystemIntent.tryParse(raw) : null)
      .where((intent) => intent != null)
      .cast<SystemIntent>()
      .handleError((Object _) {});
}
