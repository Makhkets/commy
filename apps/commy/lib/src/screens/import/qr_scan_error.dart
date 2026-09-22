import 'package:commy/gen/strings.g.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// What the scanner shows instead of a camera preview.
///
/// Its own widget rather than a closure inside the sheet, because the reason
/// the camera is unavailable decides what the screen says and that decision
/// is worth being able to see on its own: the sheet's `errorBuilder` is
/// unreachable from a widget test, where the scanner never gets far enough to
/// fail, so a closure there could only ever be checked by reading it.
///
/// The distinction it makes was missing. Every failure — including a device
/// with no camera at all — was reported as "camera access needed", which asks
/// the user for a permission that would not help; the string for the other
/// case existed in both locales and was referenced nowhere.
class QrScanError extends StatelessWidget {
  /// Creates the error view.
  const QrScanError({required this.code, super.key});

  /// Why the scanner could not start.
  final MobileScannerErrorCode code;

  /// Whether this device has no camera to ask about.
  bool get isUnsupported => code == MobileScannerErrorCode.unsupported;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    if (isUnsupported) {
      // No body: the title is the whole of it, and the privacy note about
      // the permission belongs to the case where a permission exists.
      return EmptyState(
        icon: CommyIcons.warning,
        title: t.import.qr.unavailable,
      );
    }
    return EmptyState(
      icon: CommyIcons.offline,
      title: t.import.qr.permission,
      message: t.import.qr.permissionBody,
    );
  }
}
