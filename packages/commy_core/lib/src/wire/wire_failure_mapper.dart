import 'package:commy_core/src/wire/wire_error_codes.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/services.dart';

/// Turns whatever the platform channel threw into a typed [CommyFailure].
///
/// The mapping is total on purpose: an unrecognised code becomes an
/// `UnknownFailure` and the app keeps running. A protocol that can only be
/// extended by breaking the client is a protocol nobody extends.
abstract final class WireFailureMapper {
  /// Maps a wire [code] plus its [message] onto a failure.
  ///
  /// Returns `null` for `already_running`, which is a success in disguise: the
  /// caller asked for a tunnel and the tunnel is there. Everything else is a
  /// real failure, and an unknown code still produces one.
  static CommyFailure? fromCode(String code, {String? message}) {
    final detail = message ?? '';
    if (code == WireErrorCodes.alreadyRunning) {
      return null;
    }
    if (code == WireErrorCodes.permissionDenied) {
      return const PermissionDeniedFailure();
    }
    if (code == WireErrorCodes.configInvalid) {
      return ConfigInvalidFailure(detail);
    }
    if (code == WireErrorCodes.coreCrashed) {
      return CoreCrashedFailure(detail);
    }
    if (code == WireErrorCodes.helperUnavailable ||
        code == WireErrorCodes.notRunning) {
      return const HelperUnavailableFailure();
    }
    if (code == WireErrorCodes.storage) {
      return StorageFailure(detail);
    }
    if (code == WireErrorCodes.unknown) {
      return UnknownFailure(detail, StackTrace.empty);
    }
    return UnknownFailure('$code: $detail', StackTrace.empty);
  }

  /// Maps anything caught around a channel call onto a failure.
  ///
  /// Returns `null` when the error means "already done", so the caller can
  /// treat the call as successful.
  ///
  /// A [MissingPluginException] deliberately has no code of its own: it means
  /// the platform has no tunnel implementation registered at all, which the
  /// user experiences exactly as "the service is not there".
  static CommyFailure? fromError(Object error, StackTrace stackTrace) {
    if (error is CommyFailure) {
      return error;
    }
    if (error is PlatformException) {
      return fromCode(error.code, message: error.message);
    }
    if (error is MissingPluginException) {
      return const HelperUnavailableFailure();
    }
    return UnknownFailure(error, stackTrace);
  }
}
