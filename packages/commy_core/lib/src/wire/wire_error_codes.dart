/// Error codes the native side is allowed to answer with.
///
/// A closed set. Most of them are spelled exactly like the matching
/// `CommyFailure.code`, which makes the mapping total and removes the need for
/// a synonym table. Anything not listed here becomes an `UnknownFailure`
/// rather than a crash.
abstract final class WireErrorCodes {
  /// The user declined the system VPN prompt.
  static const String permissionDenied = 'permission_denied';

  /// The configuration did not pass validation, or a tag was missing.
  static const String configInvalid = 'config_invalid';

  /// The core died.
  static const String coreCrashed = 'core_crashed';

  /// The tunnel service or privileged helper is not up.
  static const String helperUnavailable = 'helper_unavailable';

  /// A call needed a running core and there was none.
  ///
  /// Folded onto the same failure as [helperUnavailable]: from the user's seat
  /// both mean "the thing that carries traffic is not there".
  static const String notRunning = 'not_running';

  /// `start` was called while the tunnel was already up.
  ///
  /// Not a failure. The double-start contract says one tunnel, and the tunnel
  /// asked for is already there, so the call succeeded by definition.
  static const String alreadyRunning = 'already_running';

  /// A file the native side needed could not be read or written.
  static const String storage = 'storage';

  /// Anything else.
  static const String unknown = 'unknown';
}
