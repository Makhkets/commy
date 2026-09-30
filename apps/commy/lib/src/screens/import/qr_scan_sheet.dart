import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/screens/import/import_sheet.dart';
import 'package:commy/src/screens/import/qr_scan_error.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The QR scanner.
///
/// The camera is started when this sheet is built and stopped when it is
/// disposed — that is the whole lifetime of the permission, and it is what the
/// copy under the entry promises: "только на время сканирования".
///
/// The first payload that parses wins and the sheet stops scanning. Without
/// that latch a single code sitting in frame fires the import a dozen times a
/// second. A retry after a failed import opens the latch again: the scanner
/// comes back live, and it has to read the code it is shown.
class QrScanSheet extends ConsumerStatefulWidget {
  /// Creates the sheet body.
  const QrScanSheet({super.key});

  /// Opens the scanner.
  ///
  /// Through [ImportSheet.present]: a scan is the sheet most likely to be
  /// dismissed by the gesture rather than by a button, and the result it
  /// leaves behind would otherwise be what the next sheet opens on.
  static Future<void> show(BuildContext context) {
    final title = Translations.of(context).import.qr.title;
    return ImportSheet.present(
      context,
      title: title,
      builder: (context) => const QrScanSheet(),
    );
  }

  @override
  ConsumerState<QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends ConsumerState<QrScanSheet> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final state = ref.watch(importControllerProvider);
    // A retry clears the failure and hands the sheet its scanner back — a new
    // MobileScanner on the same controller, which starts the camera again.
    // The latch stayed shut, so the live preview ignored every code held up
    // to it and the only way out was to close the sheet and open it anew.
    // Keyed on the step from a result back to nothing rather than on
    // "nothing": between a detection and the import marking itself busy the
    // state is idle too, and opening the latch there would let one code in
    // frame fire the import twice.
    ref.listen<ImportState>(importControllerProvider, (previous, next) {
      final hadResult = previous != null &&
          (previous.outcome != null || previous.failure != null);
      final idle = next.outcome == null && next.failure == null && !next.isBusy;
      if (hadResult && idle) {
        _handled = false;
      }
    });

    if (state.outcome != null || state.failure != null) {
      return const ImportResultPanel();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: context.radii.lgAll,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) =>
                        QrScanError(code: error.errorCode),
                    placeholderBuilder: (context) => const Center(
                      child: CommySpinner(),
                    ),
                  ),
                  // A scanned subscription is a download of several seconds,
                  // and all the sheet showed for them was the camera stopped
                  // on its last frame — a preview that looked frozen rather
                  // than busy.
                  if (state.isBusy)
                    ColoredBox(
                      color: context.colors.bgScrim,
                      child: const Center(child: CommySpinner()),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: spacing.s4),
          Text(
            t.import.qr.permissionBody,
            style: context.typography.caption.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim() ?? '';
      if (value.isEmpty) {
        continue;
      }
      _handled = true;
      unawaited(_controller.stop());
      unawaited(
        ref.read(importControllerProvider.notifier).importText(value),
      );
      return;
    }
  }
}
