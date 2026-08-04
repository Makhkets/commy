import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/subscription_payload.dart';

/// Fetches a subscription document over HTTP.
///
/// This is the only network call the app makes on its own behalf, and it goes
/// to a host the user typed in — rule R1 is satisfied by construction.
///
/// Two things the implementation has to get right:
/// * the request goes **around** the tunnel by default, otherwise the first
///   refresh after a reinstall is impossible;
/// * the User-Agent is the honest `Commy/<version>` unless the user set an
///   override on the subscription.
abstract interface class SubscriptionFetcher {
  /// Downloads [url] and parses the metadata headers.
  ///
  /// [userAgent] overrides the default identification when the panel demands
  /// it. [throughTunnel] has no default on purpose: routing a refresh into the
  /// tunnel is a decision worth writing down at every call site.
  Future<Result<SubscriptionPayload, CommyFailure>> fetch(
    Uri url, {
    required bool throughTunnel,
    String? userAgent,
  });
}
