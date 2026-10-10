import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/dns_settings.dart';
import 'package:commy_domain/src/entities/routing.dart';
import 'package:commy_domain/src/entities/routing_profile.dart';

/// Storage of the routing policy and of the DNS policy.
///
/// Rule R6: every change written through here ends up in the generated core
/// configuration, so it has to pass the leak checklist before it ships.
abstract interface class RoutingRepository {
  /// The routing policy, refreshed on every change.
  Stream<RoutingPolicy> watch();

  /// The routing policy, once. Falls back to `RoutingPolicy.defaults`.
  Future<Result<RoutingPolicy, CommyFailure>> read();

  /// Replaces the routing policy wholesale.
  Future<Result<void, CommyFailure>> write(RoutingPolicy policy);

  /// The DNS policy, refreshed on every change.
  Stream<DnsSettings> watchDns();

  /// The DNS policy, once. Falls back to `DnsSettings.defaults`.
  Future<Result<DnsSettings, CommyFailure>> readDns();

  /// Replaces the DNS policy wholesale.
  Future<Result<void, CommyFailure>> writeDns(DnsSettings settings);

  /// The routing profiles, refreshed on every change.
  Stream<RoutingProfiles> watchProfiles();

  /// The routing profiles, once. [RoutingProfiles.empty] when none.
  Future<Result<RoutingProfiles, CommyFailure>> readProfiles();

  /// Stores [profiles] and, when given, [live] as the routing policy — in one
  /// transaction, so a switch can never leave the list naming one profile
  /// active while the rules in force are another's.
  Future<Result<void, CommyFailure>> writeProfiles(
    RoutingProfiles profiles, {
    RoutingPolicy? live,
  });
}
