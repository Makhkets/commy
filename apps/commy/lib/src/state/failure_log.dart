import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';

/// How a failure is written into the log.
///
/// The error screens and toasts are headlines that send the user to the log,
/// so the log line is where the reason has to be. Only the failure's code
/// used to go there: after "the panel's certificate was refused" the user
/// opened the log and found `subscription_unreachable`, nothing that told an
/// expired certificate from a wrong device clock.
abstract final class FailureLog {
  /// The failure's code, and what the HTTP exchange said when that is what
  /// went wrong — `subscription_unreachable (certificate: CERTIFICATE_VERIFY_
  /// FAILED: certificate has expired)`, `subscription_unreachable (status
  /// 403)`.
  ///
  /// Safe for the log (rule R3): a transport error's kind, status and detail
  /// never carry the URL — the detail is the TLS library's reason, a size, a
  /// count of redirects — and the log is redacted on top of that.
  static String describe(CommyFailure failure) {
    if (failure
        case SubscriptionUnreachableFailure(
          cause: HttpTransportError(
            :final kind,
            :final statusCode,
            :final detail
          ),
        )) {
      final status = statusCode == null ? '' : ' $statusCode';
      final why = detail == null || detail.isEmpty ? '' : ': $detail';
      return '${failure.code} ($kind$status$why)';
    }
    return failure.code;
  }
}
