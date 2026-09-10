import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/node_menu_sheet.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The long-press menu of one server: measure, copy, delete.
///
/// Deleting is the reason this file exists. It is the only irreversible thing
/// in the menu, so it has to ask first — and cancelling has to leave the row
/// exactly where it was.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  Future<void> pumpMenu(WidgetTester tester, {ProxyNode? node}) async {
    final item = node ?? testNode();
    harness = CommyTestHarness(nodes: <ProxyNode>[item]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(body: SingleChildScrollView(child: NodeMenuSheet(node: item))),
      ),
    );
    await settle(tester);
  }

  testWidgets('offers exactly measure, copy and delete', (tester) async {
    await pumpMenu(tester);

    expect(find.text(t.node.measure), findsOneWidget);
    expect(find.text(t.node.copyLink), findsOneWidget);
    expect(find.text(t.node.delete), findsOneWidget);
  });

  testWidgets('copying puts the share link on the clipboard and says so',
      (tester) async {
    await pumpMenu(tester);

    await tester.tap(find.text(t.node.copyLink));
    await tester.pumpAndSettle();

    expect(harness.clipboard.text, startsWith('vless://'));
    expect(find.text(t.node.linkCopied), findsOneWidget);
  });

  testWidgets('a protocol with no link format is told, not silently skipped',
      (tester) async {
    await pumpMenu(
      tester,
      node: const ProxyNode(
        id: 'wg-1',
        name: 'Home',
        protocol: Protocol.wireguard,
        host: 'wg.example.net',
        port: 51820,
      ),
    );

    await tester.tap(find.text(t.node.copyLink));
    await tester.pumpAndSettle();

    expect(harness.clipboard.text, isNull);
    expect(find.text(t.node.noLink), findsOneWidget);
  });

  group('delete', () {
    testWidgets('asks first, and cancelling keeps the server', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(t.node.delete));
      await tester.pumpAndSettle();

      expect(find.text(t.node.deleteConfirm.title), findsOneWidget);
      expect(find.text(t.node.deleteConfirm.body), findsOneWidget);
      // Nothing is running, so the disconnection warning stays away.
      expect(find.text(t.node.deleteConfirm.inUse), findsNothing);

      await tester.tap(find.text(t.node.deleteConfirm.cancel));
      await tester.pumpAndSettle();

      expect(harness.nodeRepository.nodes, hasLength(1));
    });

    testWidgets('confirming removes it', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(t.node.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.node.deleteConfirm.confirm));
      await tester.pumpAndSettle();

      expect(harness.nodeRepository.nodes, isEmpty);
    });
  });
}
