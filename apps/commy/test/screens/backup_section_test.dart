import 'dart:convert';
import 'dart:typed_data';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/screens/settings/backup_section.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';
import '../support/fake_repositories.dart';

/// G10. The two flows are chains of sheets, and each link is a place the user
/// can stop; the assertions are about what was written — a file, the
/// repositories — and what was said, at every stop.
void main() {
  final t = Translations();
  const password = 'eight chars+';

  final oldSubscription = Subscription(
    id: 'sub-old',
    name: 'Old panel',
    url: Uri.parse('https://old.example.com/sub/OLDTOKEN'),
  );
  const oldServer = ProxyNode(
    id: 'old-server',
    name: 'Old',
    protocol: Protocol.trojan,
    host: 'old.example.com',
    port: 443,
    subscriptionId: 'sub-old',
    params: <String, Object?>{'password': 'old-secret'},
  );

  final restoredSubscription = Subscription(
    id: 'sub-new',
    name: 'Restored panel',
    url: Uri.parse('https://new.example.com/sub/NEWTOKEN'),
  );
  const restoredServer = ProxyNode(
    id: 'new-server',
    name: 'Finland',
    protocol: Protocol.vless,
    host: 'fi.example.com',
    port: 443,
    subscriptionId: 'sub-new',
    params: <String, Object?>{'uuid': '8f3c1e6a-9d2b-4c7f-a1e5-0b6d4a2c9f88'},
  );

  late CommyTestHarness harness;
  late _QuietSystemSettings system;

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    harness = CommyTestHarness(
      subscriptions: <Subscription>[oldSubscription],
      nodes: const <ProxyNode>[oldServer],
    );
    addTearDown(harness.dispose);
    system = _QuietSystemSettings();
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(body: ListView(children: const <Widget>[BackupSection()])),
        extra: <Override>[systemSettingsProvider.overrideWithValue(system)],
      ),
    );
    await tester.pumpAndSettle();
  }

  Uint8List backupFile({
    List<String> ruleSets = const <String>[],
    bool blockAds = false,
    String filePassword = password,
  }) {
    final snapshot = BackupSnapshot(
      createdAt: DateTime.utc(2026, 9, 20),
      appVersion: '0.1.0-alpha.10',
      platform: 'android',
      subscriptions: <Subscription>[restoredSubscription],
      nodes: const <ProxyNode>[restoredServer],
      routing: RoutingPolicy(
        blockAds: blockAds,
        rules: const <RoutingRule>[
          RoutingRule(
            id: 'r1',
            matcher: 'domain:ru',
            action: RuleAction.direct,
          ),
        ],
      ),
      settings: const AppSettings(autoConnect: true),
      selectedNodeId: restoredServer.id,
      ruleSets: ruleSets,
    );
    return FakeBackupCipher.sealed(
      Uint8List.fromList(utf8.encode(jsonEncode(snapshot.toJson()))),
      filePassword,
    );
  }

  Finder field(int index) => find.byType(TextField).at(index);

  group('saving a backup', () {
    testWidgets('asks for a password twice, seals, and saves one file',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text(t.settings.backup.export));
      await tester.pumpAndSettle();
      expect(find.text(t.settings.backup.password.exportBody), findsOneWidget);
      await tester.enterText(field(0), password);
      await tester.enterText(field(1), password);
      await tester.tap(find.text(t.settings.backup.password.save));
      await tester.pumpAndSettle();

      expect(
        harness.backupFiles.saved.keys.single,
        matches(RegExp(r'^commy-\d{4}-\d{2}-\d{2}\.commybackup$')),
      );
      final sealed = harness.backupFiles.saved.values.single;
      final opened =
          (await harness.backupCipher.open(sealed, password)).valueOrNull!;
      final json = jsonDecode(utf8.decode(opened)) as Map<String, Object?>;
      expect(json['format'], BackupSnapshot.format);
      final nodes = json['nodes']! as List<Object?>;
      expect((nodes.single! as Map)['params'], oldServer.params);
      expect(find.textContaining('1 подписка, 1 сервер'), findsOneWidget);
      // The sheet is gone and the password with it.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a short password is refused before anything is sealed',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text(t.settings.backup.export));
      await tester.pumpAndSettle();
      await tester.enterText(field(0), 'short');
      await tester.enterText(field(1), 'short');
      await tester.tap(find.text(t.settings.backup.password.save));
      await tester.pumpAndSettle();

      expect(
        find.text(
          t.settings.backup.password
              .tooShort(min: ExportBackupUseCase.minPasswordLength),
        ),
        findsOneWidget,
      );
      expect(harness.backupFiles.saved, isEmpty);
    });

    testWidgets('two passwords that differ are refused', (tester) async {
      await pump(tester);

      await tester.tap(find.text(t.settings.backup.export));
      await tester.pumpAndSettle();
      await tester.enterText(field(0), password);
      await tester.enterText(field(1), '${password}x');
      await tester.tap(find.text(t.settings.backup.password.save));
      await tester.pumpAndSettle();

      expect(find.text(t.settings.backup.password.mismatch), findsOneWidget);
      expect(harness.backupFiles.saved, isEmpty);
    });

    testWidgets('a closed save dialog says nothing was saved', (tester) async {
      await pump(tester);
      harness.backupFiles.saveAccepted = false;

      await tester.tap(find.text(t.settings.backup.export));
      await tester.pumpAndSettle();
      await tester.enterText(field(0), password);
      await tester.enterText(field(1), password);
      await tester.tap(find.text(t.settings.backup.password.save));
      await tester.pumpAndSettle();

      expect(find.text(t.settings.backup.notSaved), findsOneWidget);
    });
  });

  group('restoring a backup', () {
    testWidgets('no file picked is no question asked', (tester) async {
      await pump(tester);

      await tester.tap(find.text(t.settings.backup.restore));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(harness.nodeRepository.nodes, const <ProxyNode>[oldServer]);
    });

    testWidgets('a file that is not a backup is turned away before a password',
        (tester) async {
      await pump(tester);
      harness.backupFiles.toPick =
          Uint8List.fromList(utf8.encode('vless://not-a-backup'));

      await tester.tap(find.text(t.settings.backup.restore));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text(t.error.backup.notABackup), findsOneWidget);
    });

    testWidgets('a wrong password stays in the sheet; the right one asks, '
        'then replaces everything', (tester) async {
      await pump(tester);
      harness.backupFiles.toPick = backupFile();

      await tester.tap(find.text(t.settings.backup.restore));
      await tester.pumpAndSettle();
      await tester.enterText(field(0), 'not the password');
      await tester.tap(find.text(t.settings.backup.password.open));
      await tester.pumpAndSettle();

      expect(find.text(t.error.backup.wrongPassword), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(field(0), password);
      await tester.tap(find.text(t.settings.backup.password.open));
      await tester.pumpAndSettle();

      // The question names what is in the file before anything changes.
      expect(find.text(t.settings.backup.restoreConfirm.title), findsOneWidget);
      expect(find.textContaining('20.09.2026'), findsOneWidget);
      expect(harness.nodeRepository.nodes, const <ProxyNode>[oldServer]);

      await tester.tap(find.text(t.settings.backup.restoreConfirm.confirm));
      await tester.pumpAndSettle();

      expect(harness.subscriptionRepository.items, <Subscription>[
        restoredSubscription,
      ]);
      expect(harness.nodeRepository.nodes, const <ProxyNode>[restoredServer]);
      expect(harness.settingsRepository.selectedNodeId, restoredServer.id);
      expect(
        (await harness.settingsRepository.read()).valueOrNull!.autoConnect,
        isTrue,
      );
      expect(
        (await harness.routingRepository.read()).valueOrNull!.rules.single.id,
        'r1',
      );
      expect(find.textContaining('Восстановлено'), findsOneWidget);
      // The boot receiver follows the restored setting.
      expect(system.startOnBootCalls, <bool>[false]);
    });

    testWidgets('saying no to the question changes nothing', (tester) async {
      await pump(tester);
      harness.backupFiles.toPick = backupFile();

      await tester.tap(find.text(t.settings.backup.restore));
      await tester.pumpAndSettle();
      await tester.enterText(field(0), password);
      await tester.tap(find.text(t.settings.backup.password.open));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settings.backup.restoreConfirm.cancel));
      await tester.pumpAndSettle();

      expect(harness.nodeRepository.nodes, const <ProxyNode>[oldServer]);
      expect(harness.subscriptionRepository.items, <Subscription>[
        oldSubscription,
      ]);
    });

    testWidgets('rule sets that are not on this phone are named, with a way '
        'to get them', (tester) async {
      await pump(tester);
      // Ad blocking needs its list, and this phone has never downloaded it.
      harness.backupFiles.toPick = backupFile(blockAds: true);

      await tester.tap(find.text(t.settings.backup.restore));
      await tester.pumpAndSettle();
      await tester.enterText(field(0), password);
      await tester.tap(find.text(t.settings.backup.password.open));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settings.backup.restoreConfirm.confirm));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(t.settings.backup.ruleSetsMissing),
        findsOneWidget,
      );
      // No router in this harness, so no button; the app always has one.
      expect(find.text(t.settings.backup.ruleSetsAction), findsNothing);
    });
  });
}

/// The system settings without a channel: awaiting a real one inside
/// `testWidgets` never completes (see settings_screen_test.dart).
class _QuietSystemSettings extends SystemSettings {
  final List<bool> startOnBootCalls = <bool>[];

  @override
  Future<bool> setStartOnBoot({required bool enabled}) async {
    startOnBootCalls.add(enabled);
    return true;
  }
}
