import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';

/// Who this installation says it is when it asks a panel for a subscription.
///
/// Panels that limit devices per subscription — Remnawave and the ones
/// compatible with it — count them by an identifier the client sends. A client
/// that sends none is, to such a panel, unsupported: it answers with a single
/// placeholder server named "App not supported" instead of the list. Happ,
/// INCY and v2RayTun all send one, and the owner's decision of 2026-09-18 is
/// that Commy does too.
///
/// What it is, and what it is not:
///
/// * an identifier of this **installation** — a random UUID made on first
///   need. Not `ANDROID_ID`, not a serial number, not a MAC. The panel needs a
///   stable key for a counter, not a fingerprint of the hardware; reinstalling
///   or [reset] yields a new one;
/// * sent **only** with subscription requests, which go to the host the user
///   entered. Rule R1 is about hosts, and no new host learns anything;
/// * **off** the moment the user says so — [subscriptionHeaders] is then
///   empty, not partially filled.
abstract interface class DeviceIdentity {
  /// Header that carries the identifier. The name Remnawave reads.
  static const String hwidHeader = 'x-hwid';

  /// Header that carries the operating system's name.
  static const String osHeader = 'x-device-os';

  /// Header that carries the operating system's version.
  static const String osVersionHeader = 'x-ver-os';

  /// Header that carries the device model.
  static const String modelHeader = 'x-device-model';

  /// The headers a subscription request carries, or none at all when the user
  /// switched the identifier off.
  ///
  /// Never throws. A store that cannot be read yields no headers: a refresh
  /// that fails because of an *optional* identifier would be a worse outcome
  /// than a panel answering as it does to any client without one.
  Future<Map<String, String>> subscriptionHeaders();

  /// Forgets the identifier. The next request makes a new one.
  Future<Result<void, CommyFailure>> reset();
}
