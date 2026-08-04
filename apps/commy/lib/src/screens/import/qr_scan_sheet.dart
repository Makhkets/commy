import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
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
/// second.
class QrScanSheet extends ConsumerStatefulWidget {
  /// Creates the sheet body.
  const QrScanSheet({super.key});

  /// Opens the scanner.
  static Future<void> show(BuildContext context) {
    final title = Translations.of(context).import.qr.title;
    return CommySheet.show<void>(
      context: context,
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
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => EmptyState(
                  icon: CommyIcons.offline,
                  title: t.import.qr.permission,
                  message: t.import.qr.permissionBody,
                ),
                placeholderBuilder: (context) => const Center(
                  child: CommySpinner(),
                ),
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
