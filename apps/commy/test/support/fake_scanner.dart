import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A camera that reads whatever the test holds up to it.
class FakeScanner extends MobileScannerPlatform {
  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();

  /// How many times the camera was started.
  int starts = 0;

  /// Puts a QR code holding [value] in front of the camera.
  void show(String value) {
    _barcodes.add(
      BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: value)]),
    );
  }

  Future<void> close() => _barcodes.close();

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream<TorchState>.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream<double>.empty();

  @override
  Widget buildCameraView() => const SizedBox.expand();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts++;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 640),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> setFocusPoint(Offset position) async {}

  @override
  Future<void> dispose() async {}
}
