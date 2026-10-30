import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/components/commy_tone.dart';

/// The six states the top of the main screen can be in.
///
/// This is the domain's [TunnelStatus] with the payload dropped: the route
/// draws legs and stops, and none of that depends on *when* the tunnel came
/// up or *which* failure took it down. Keeping the two types apart means a
/// widget test can name a state in one word, and it keeps the painter from
/// having to switch over classes that carry data it must not read.
///
/// Use [ConnectState.of] at the edge of the presentation layer and pass the
/// result down; the mapping is total, so a seventh tunnel state would break
/// the build here rather than silently render as idle.
enum ConnectState {
  /// Nothing is running. Both legs of the route are dashed.
  idle,

  /// The core was asked to start. The first leg is being built.
  starting,

  /// The tunnel is up and reachability is being probed. A raised tunnel is
  /// not yet working internet, and the user has to see the difference.
  checking,

  /// The tunnel is up and confirmed. Both legs are solid.
  connected,

  /// The core was asked to stop and has not finished yet.
  stopping,

  /// The tunnel is down because something went wrong.
  error;

  /// Projects a domain [status] onto the state the button draws.
  static ConnectState of(TunnelStatus status) => switch (status) {
        TunnelIdle() => ConnectState.idle,
        TunnelStarting() => ConnectState.starting,
        TunnelChecking() => ConnectState.checking,
        TunnelConnected() => ConnectState.connected,
        TunnelStopping() => ConnectState.stopping,
        TunnelError() => ConnectState.error,
      };

  /// Whether the tunnel carries traffic — [checking] or [connected].
  ///
  /// What the metrics strip asks before it decides between live figures and
  /// zeros, and what says whether a session timer is running.
  bool get isTunnelUp =>
      this == ConnectState.checking || this == ConnectState.connected;

  /// Whether the core is between two states: [starting] or [stopping].
  bool get isTransitional =>
      this == ConnectState.starting || this == ConnectState.stopping;

  /// Whether the "check" action belongs on screen.
  ///
  /// Only while the tunnel is up: there is nothing to check before it is,
  /// and a button that cannot do anything is worse than no button.
  bool get showsCheckButton => isTunnelUp;

  /// The meaning to hand a chip or banner sitting next to the route.
  ///
  /// [stopping] answers [CommyTone.idle] rather than
  /// [CommyTone.connecting] on purpose: the route is already fading back to
  /// its dashes, and a chip that disagreed with it right beside it would be a
  /// bug the eye catches immediately.
  CommyTone get tone => switch (this) {
        ConnectState.idle => CommyTone.idle,
        ConnectState.starting => CommyTone.connecting,
        ConnectState.checking => CommyTone.connected,
        ConnectState.connected => CommyTone.connected,
        ConnectState.stopping => CommyTone.idle,
        ConnectState.error => CommyTone.error,
      };
}
