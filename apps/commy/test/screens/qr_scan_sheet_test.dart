import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/screens/import/qr_scan_sheet.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../support/commy_test_app.dart';

/// The QR scanner after a scanned import has failed.
///
/// The sheet reads the first code and then stops listening, so one code held
/// in frame does not fire the import a dozen times a second. A retry brings
/// the live camera back, and the latch stayed shut: the preview ignored every
/// code it was shown until the sheet was closed and opened again.
void main() {
  final t = Translations();
  const link = 'https://panel.example.net/sub/token';

  late MobileScannerPlatform original;
  late _FakeScanner scanner;

  setUp(() {
    original = MobileScannerPlatform.instance;
    scanner = _FakeScanner();
    MobileScannerPlatform.instance = scanner;
  });

  tearDown(() async {
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
    await scanner.close();
  });

  Future<CommyTestHarness> pumpSheet(
    WidgetTester tester, {
    List<Override> extra = const <Override>[],
  }) async {
    tester.view
      ..physicalSize = const Size(420, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = CommyTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.wrap(
        const Scaffold(body: SingleChildScrollView(child: QrScanSheet())),
        extra: extra,
      ),
    );
    await settle(tester);
    return harness;
  }

  testWidgets('a retry after a failed import scans again', (tester) async {
    final failure = SubscriptionUnreachableFailure(
      url: Uri.parse(link),
      cause: 'the panel did not answer',
    );
    final harness = await pumpSheet(tester);
    harness.subscriptionFetcher.failure = failure;

    scanner.show(link);
    await settle(tester);
    expect(harness.subscriptionFetcher.callCount, 1);

    final retry = FailureText.of(failure, t);
    expect(retry.action, FailureAction.retry);
    await tester.tap(find.text(retry.actionLabel));
    await settle(tester);
    expect(scanner.starts, 2, reason: 'The retry brings the camera back.');

    harness.subscriptionFetcher.failure = null;
    scanner.show(link);
    await settle(tester);

    expect(
      harness.subscriptionFetcher.callCount,
      2,
      reason: 'A live camera that ignores the code it is shown is the bug.',
    );
  });

  testWidgets('one code held in frame imports once', (tester) async {
    final harness = await pumpSheet(tester);
    harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
      url: Uri.parse(link),
      cause: 'the panel did not answer',
    );

    scanner
      ..show(link)
      ..show(link)
      ..show(link);
    await settle(tester);

    expect(harness.subscriptionFetcher.callCount, 1);
  });

  testWidgets('a download in flight shows it is busy', (tester) async {
    final harness = await pumpSheet(tester);
    final gate = harness.subscriptionFetcher.gate = Completer<void>();
    expect(find.byType(CommySpinner), findsNothing);

    scanner.show(link);
    await settle(tester);

    expect(find.byType(CommySpinner), findsOneWidget);

    gate.complete();
    await settle(tester);
  });
}

/// A camera that reads whatever the test holds up to it.
class _FakeScanner extends MobileScannerPlatform {
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
