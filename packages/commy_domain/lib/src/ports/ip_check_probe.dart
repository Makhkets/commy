import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/ip_check_result.dart';

/// Asks an external service which address the tunnel exits from.
///
/// Exception E-1 of docs/09-security-privacy.md, and every clause of it is a
/// constraint on the implementation: the request goes **through** the tunnel
/// — around it the answer is the user's real address and the check is worse
/// than none — to the endpoint the user configured, carries no identifier of
/// the device, the install or the user, and its answer is shown once and not
/// stored. When it fires is the caller's business: by button press, never on
/// its own.
abstract interface class IpCheckProbe {
  /// Sends one request to [endpoint] and reads the address out of the answer.
  Future<Result<IpCheckResult, CommyFailure>> probe(Uri endpoint);
}
