import 'package:commy_core/src/android/android_core_client.dart';
import 'package:commy_core/src/fake/fake_core_client.dart';
import 'package:commy_core/src/logging/app_logger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';

/// Picks the `CoreClient` implementation the current platform can honour.
///
/// The five platforms run the core in five different places — in-process under
/// `VpnService`, in a Network Extension, in an elevated service, behind a
/// privileged helper — and ADR-0005 hides all of that behind one interface.
/// This is the only place that is allowed to know which one is which.
///
/// ## Unsupported platforms get the fake, not an exception
///
/// Throwing here would mean the app cannot be opened at all on a machine whose
/// tunnel is not written yet, and the tunnel is exactly one screen out of ten.
/// Handing back [FakeCoreClient] keeps the other nine reviewable on the desktop
/// the app is being written on, which is worth far more than the purity of
/// refusing to start.
///
/// The fake is loud about being a fake: it reports synthetic node tags and its
/// own log tag, so nobody mistakes it for a working tunnel for long.
abstract final class CoreClientFactory {
  /// Builds the client for [platform], defaulting to the running one.
  ///
  /// [logger] receives the client's own diagnostics, not the core log.
  static CoreClient create({AppLogger? logger, TargetPlatform? platform}) {
    final target = platform ?? defaultTargetPlatform;
    if (!supports(target)) {
      logger?.info(
        'no tunnel for ${target.name}; running on the fake core',
        tag: FakeCoreClient.logTag,
      );
      return FakeCoreClient(logger: logger);
    }
    return AndroidCoreClient(logger: logger);
  }

  /// Whether [platform] has a real tunnel behind it today.
  ///
  /// Android only, as of M1. Apple, Windows and Linux land in later milestones
  /// (docs/07-roadmap.md); until then they answer `false` and get the fake.
  static bool supports(TargetPlatform platform) =>
      platform == TargetPlatform.android;
}
