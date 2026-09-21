import 'package:commy/gen/strings.g.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Shows one payload as a QR code.
///
/// The other half of the import path: `mobile_scanner` has been able to read a
/// code since the import sheet existed, and until now nothing could produce
/// one — so moving a server to a second phone meant copying a link into a
/// messenger, which is the one place a credential should never go.
///
/// It renders text and nothing else. What that text is — a share link, a
/// subscription URL — is `QrPayload`'s decision, and whether the user has
/// agreed to put it on a screen is the caller's; a sheet is far too late to
/// ask.
class QrSheet extends StatelessWidget {
  /// Creates the sheet body.
  const QrSheet({
    required this.payload,
    required this.caption,
    this.warning,
    super.key,
  });

  /// The text the code carries.
  final String payload;

  /// What the code is of, under the image. The server or subscription name.
  final String caption;

  /// Said above the code when scanning it hands over a credential.
  final String? warning;

  /// Opens the sheet, or a dialog on a wide window.
  static Future<void> show({
    required BuildContext context,
    required String payload,
    required String caption,
    String? title,
    String? warning,
  }) {
    return CommySheet.show<void>(
      context: context,
      title: title,
      builder: (context) => QrSheet(
        payload: payload,
        caption: caption,
        warning: warning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final alert = warning;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (alert != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  CommyIcons.warning,
                  size: CommySizes.iconControl,
                  color: colors.statusConnecting,
                ),
                SizedBox(width: spacing.s2),
                Expanded(
                  child: Text(
                    alert,
                    style: context.typography.caption.copyWith(
                      color: colors.statusConnecting,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.s4),
          ],
          Center(
            // The card carries its own light ground rather than the screen's.
            // A QR is read by contrast and a decoder expects dark modules on
            // a light quiet zone; drawn in the dark theme's colours it fails
            // silently, which is the worst way for a share button to fail.
            child: Container(
              padding: const EdgeInsets.all(CommySizes.qrQuietZone),
              decoration: BoxDecoration(
                color: CommyQrPalette.ground,
                borderRadius: radii.mdAll,
              ),
              child: QrImageView(
                data: payload,
                size: CommySizes.qrSize,
                // Explicit, because the default follows the ambient theme and
                // would undo the paragraph above.
                backgroundColor: CommyQrPalette.ground,
                // eyeStyle and dataModuleStyle are left alone deliberately.
                // Their defaults are black squares, which is the shape a
                // decoder is looking for; naming the colour and nothing else
                // sets the shape to null, and the painter reads that as round
                // dots — smaller marks with gaps between them, which is a
                // worse code for no reason. Restyling them to say
                // `CommyQrPalette.module` would be writing out the default.
                //
                // Error correction M rather than the package's L: this code is
                // read off one screen by another camera, and the redundancy is
                // what survives a reflection. Capacity at version 40 drops to
                // 2 331 bytes, still above `QrPayload.maxLength`, so the guard
                // that refuses an unscannable payload is unaffected.
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                // The quiet zone is the padding above, drawn at a size we
                // chose; asking the painter for a second one inside the image
                // only makes the modules smaller.
                padding: EdgeInsets.zero,
                // A code nothing can read is worth an error rather than a
                // blank square: `QrPayload` refuses anything past its own
                // limit, so reaching this means a version the encoder itself
                // will not produce.
                errorStateBuilder: (context, error) => _Unrenderable(
                  message: t.qr.tooLong,
                ),
              ),
            ),
          ),
          SizedBox(height: spacing.s3),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: context.typography.caption.copyWith(
              color: colors.textTertiary,
            ),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }
}

/// Drawn in place of a code the encoder refused.
class _Unrenderable extends StatelessWidget {
  const _Unrenderable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CommySizes.qrSize,
      height: CommySizes.qrSize,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.typography.caption.copyWith(
            // On the code's own light ground, not the screen's.
            color: CommyQrPalette.module,
          ),
        ),
      ),
    );
  }
}
