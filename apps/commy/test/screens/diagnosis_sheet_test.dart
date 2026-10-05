import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/diagnosis/diagnosis_sheet.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';
import '../support/fake_network_diagnostics.dart';

void main() {
  final t = Translations();
  final node = testNode(subscriptionId: 'sub-1');

  Future<CommyTestHarness> pump(
    WidgetTester tester, {
    void Function(FakeNetworkDiagnostics network)? network,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = CommyTestHarness(nodes: <ProxyNode>[node]);
    addTearDown(harness.dispose);
    network?.call(harness.network);
    final sheet = SingleChildScrollView(child: DiagnosisSheet(node: node));
    await tester.pumpWidget(
      harness.wrap(Scaffold(body: sheet)),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('a working server is said to work, every layer ticked',
      (tester) async {
    await pump(tester);

    expect(find.text(t.diagnosis.verdict.works), findsOneWidget);
    expect(find.text(t.diagnosis.steps.dns), findsOneWidget);
    expect(find.text(t.diagnosis.steps.tls), findsOneWidget);
  });

  testWidgets('a name that does not resolve is named, with what to do',
      (tester) async {
    await pump(tester, network: (network) => network.addresses = null);

    expect(find.text(t.diagnosis.verdict.dnsFailed), findsOneWidget);
    expect(find.text(t.diagnosis.verdict.dnsFailedBody), findsOneWidget);
  });

  testWidgets('the protocol refusing is told apart from the network',
      (tester) async {
    final harness = await pump(tester);
    harness.core.setLatency(SingBoxTags.forNode(node), null);

    await tester.tap(find.text(t.diagnosis.retry));
    await tester.pumpAndSettle();

    expect(find.text(t.diagnosis.verdict.protocolRefused), findsOneWidget);
  });
}
