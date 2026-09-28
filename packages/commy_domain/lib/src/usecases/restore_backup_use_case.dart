import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/backup_snapshot.dart';
import 'package:commy_domain/src/entities/routing.dart';
import 'package:commy_domain/src/entities/rule_set.dart';
import 'package:commy_domain/src/ports/library_store.dart';
import 'package:commy_domain/src/ports/routing_repository.dart';
import 'package:commy_domain/src/ports/rule_set_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Makes a backup the user's data: replaces what the phone has with it.
///
/// Replace, not merge. Settings, routing and DNS are one object each, and
/// "merge" means nothing for them; for servers it would mean deciding which
/// of two same-named subscriptions wins and whose rules come first — choices
/// a user should make with the two lists in front of them, not by accident of
/// a file. The screen says "everything will be replaced" before this runs.
///
/// No network. The subscriptions come back with their servers, so the phone
/// works right away even where the panel is blocked outside a tunnel; the
/// scheduler refreshes them later, as it always does, only from the user's
/// own hosts (rule R1). Rule-set files are named, not fetched: the outcome
/// lists what is missing, and downloading stays a tap (exception E-2).
///
/// Stays out of the tunnel's way by contract, not by checking: the caller
/// disconnects first. A reload fired halfway through a replaced library would
/// build a config from half of it.
class RestoreBackupUseCase {
  /// Creates the use case.
  const RestoreBackupUseCase({
    required this.library,
    required this.settings,
    required this.routing,
    required this.ruleSets,
    required this.platform,
    required this.requiredRuleSets,
  });

  /// Where subscriptions, groups and servers are replaced, in one go.
  final LibraryStore library;

  /// Where the app's settings and the selected server are written.
  final SettingsRepository settings;

  /// Where routing and DNS are written.
  final RoutingRepository routing;

  /// Which rule sets this phone already has.
  final RuleSetRepository ruleSets;

  /// The platform this runs on (`android`, `ios`, …).
  final String platform;

  /// The rule sets a routing policy needs on this platform — the config
  /// builder's own answer, passed in because the domain does not know how
  /// sing-box names them. What is missing after a restore is what the
  /// restored rules need and this phone lacks, not what the other phone had.
  final List<String> Function(RoutingPolicy routing) requiredRuleSets;

  /// Replaces the library, routing, DNS and settings with [snapshot]'s.
  ///
  /// The library goes first: it is the part that can fail in interesting
  /// ways, and if it does, nothing else has changed yet. Returns the rule
  /// sets the restored rules need and this phone does not have, and whether
  /// the per-app list had to be dropped because it names another platform's
  /// apps.
  Future<
      Result<({List<String> missingRuleSets, bool perAppDropped}),
          CommyFailure>> call(BackupSnapshot snapshot) async {
    final replaced = await library.replaceLibrary(
      subscriptions: snapshot.subscriptions,
      groups: snapshot.groups,
      nodes: snapshot.nodes,
    );
    if (replaced case Err(:final failure)) {
      return Err(failure);
    }
    // Right after the library, not last: if anything below fails, the
    // selection must not be left naming a server that no longer exists.
    // Null included — the old selection is gone with the old library.
    final selected =
        await settings.writeSelectedNodeId(snapshot.selectedNodeId);
    if (selected case Err(:final failure)) {
      return Err(failure);
    }

    var perAppDropped = false;
    final policy = snapshot.routing;
    if (policy != null) {
      // Package names mean nothing to a desktop and executables nothing to a
      // phone. An allow list of apps that do not exist here would tunnel
      // nothing at all; better to say so and start from "every app".
      final foreign = snapshot.platform != platform &&
          policy.perAppMode != PerAppMode.disabled;
      perAppDropped = foreign;
      final written = await routing.write(
        foreign
            ? policy.copyWith(
                perAppMode: PerAppMode.disabled,
                perAppPackages: const <String>[],
              )
            : policy,
      );
      if (written case Err(:final failure)) {
        return Err(failure);
      }
    }
    final dns = snapshot.dns;
    if (dns != null) {
      final written = await routing.writeDns(dns);
      if (written case Err(:final failure)) {
        return Err(failure);
      }
    }
    final appSettings = snapshot.settings;
    if (appSettings != null) {
      final written = await settings.write(appSettings);
      if (written case Err(:final failure)) {
        return Err(failure);
      }
    }
    var missing = const <String>[];
    final restored = policy == null
        ? null
        : (perAppDropped
            ? policy.copyWith(
                perAppMode: PerAppMode.disabled,
                perAppPackages: const <String>[],
              )
            : policy);
    if (restored != null) {
      final present = <String>{
        for (final set
            in (await ruleSets.list()).valueOrNull ?? const <RuleSet>[])
          set.tag,
      };
      missing = <String>[
        for (final tag in requiredRuleSets(restored))
          if (!present.contains(tag)) tag,
      ];
    }
    return Ok((missingRuleSets: missing, perAppDropped: perAppDropped));
  }
}
