import 'package:commy_data/src/http/http_transport_error.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';

/// Turns whatever dio throws into a domain failure.
///
/// Everything transport-level becomes `subscriptionUnreachable`. That is the
/// only variant in the closed failure set that fits a network problem, and
/// widening the set is a decision for the domain, not for an adapter
/// (docs/02-architecture.md, "Обработка ошибок"). The distinction the user
/// actually needs — timeout versus 403 versus bad certificate — survives inside
/// `HttpTransportError`, so the UI can still say something specific.
abstract final class NetworkFailureMapper {
  /// Maps a dio exception raised while fetching [url].
  static CommyFailure fromDio(DioException error, Uri url) {
    final transport = switch (error.type) {
      DioExceptionType.connectionTimeout => const HttpTransportError(
          kind: HttpTransportError.kindTimeout,
          detail: 'connect',
        ),
      DioExceptionType.sendTimeout => const HttpTransportError(
          kind: HttpTransportError.kindTimeout,
          detail: 'send',
        ),
      DioExceptionType.receiveTimeout => const HttpTransportError(
          kind: HttpTransportError.kindTimeout,
          detail: 'receive',
        ),
      // Added in dio 5.11. Kept explicit rather than folded into a wildcard so
      // that the next variant dio introduces breaks the build here, where the
      // decision belongs, instead of quietly becoming "unknown".
      DioExceptionType.transformTimeout => const HttpTransportError(
          kind: HttpTransportError.kindTimeout,
          detail: 'transform',
        ),
      DioExceptionType.badCertificate => const HttpTransportError(
          kind: HttpTransportError.kindCertificate,
        ),
      DioExceptionType.badResponse => HttpTransportError(
          kind: HttpTransportError.kindStatus,
          statusCode: error.response?.statusCode,
        ),
      DioExceptionType.cancel => const HttpTransportError(
          kind: HttpTransportError.kindCancelled,
        ),
      DioExceptionType.connectionError => const HttpTransportError(
          kind: HttpTransportError.kindConnection,
        ),
      DioExceptionType.unknown => HttpTransportError(
          kind: HttpTransportError.kindUnknown,
          detail: error.error?.runtimeType.toString(),
        ),
    };
    return CommyFailure.subscriptionUnreachable(
      url: url,
      cause: transport,
    );
  }

  /// Maps anything else thrown while fetching [url].
  static CommyFailure fromError(Object error, Uri url) {
    if (error is DioException) {
      return fromDio(error, url);
    }
    return CommyFailure.subscriptionUnreachable(
      url: url,
      cause: HttpTransportError(
        kind: HttpTransportError.kindUnknown,
        detail: error.runtimeType.toString(),
      ),
    );
  }

  /// The failure for a body we refuse to load into memory.
  static CommyFailure tooLarge(Uri url, int limitBytes) =>
      CommyFailure.subscriptionUnreachable(
        url: url,
        cause: HttpTransportError(
          kind: HttpTransportError.kindTooLarge,
          detail: '> $limitBytes bytes',
        ),
      );
}
