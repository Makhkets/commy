import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/settings/dns_screen.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #11: `DnsSettings` was modelled and generated from the first
/// release, and the row on the routing screen showed a value nobody could
/// change.
///
/// The assertions that matter are the two the configuration depends on: what
/// the screen refuses to store, and the cache switch that the builder
/// overrides while FakeIP is on.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  Future<void> pumpScreen(WidgetTester tester, {DnsSettings? dns}) async {
    // Taller than the 800x600 default: the screen is three sections and a
    // paragraph, and a surface that cuts the extras off would be testing the
    // window rather than the screen.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    if (dns != null) {
      await harness.routingRepository.writeDns(dns);
    }
    await tester.pumpWidget(harness.wrap(const DnsScreen()));
    await settle(tester);
  }

  DnsSettings stored() => harness.routingRepository.dns;

  testWidgets('shows both resolvers, the strategy and the extras',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.dns.remote), findsOneWidget);
    expect(find.text(DnsSettings.defaultRemote), findsOneWidget);
    expect(find.text(t.dns.direct), findsOneWidget);
    expect(find.text(t.dns.strategyPreferIpv4), findsOneWidget);
    expect(find.text(t.dns.fakeIp), findsOneWidget);
    // The two-resolver explanation is the point of the screen, not decoration.
    expect(find.text(t.dns.footer), findsOneWidget);
  });

  testWidgets('picking a strategy stores it', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(t.dns.strategyIpv6Only));
    await tester.pumpAndSettle();

    expect(stored().strategy, DnsStrategy.ipv6Only);
  });

  group('the resolver editor', () {
    testWidgets('stores a resolver the core can build', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(t.dns.remote));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CommyTextField),
        'https://dns.example.net/dns-query',
      );
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(stored().remote, 'https://dns.example.net/dns-query');
    });

    testWidgets('refuses a scheme the core has no transport for',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(t.dns.remote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), 'dhcp://auto');
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(find.text(t.dns.edit.unsupportedScheme), findsOneWidget);
      // Nothing was written: the typo is refused where it was made, not two
      // screens away on the next connect.
      expect(stored().remote, DnsSettings.defaultRemote);
    });

    testWidgets('refuses a scheme with no address behind it', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(t.dns.direct));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), 'tls://');
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(find.text(t.dns.edit.missingAddress), findsOneWidget);
      expect(stored().direct, DnsSettings.defaultDirect);
    });

    testWidgets('everything it accepts, the builder can build', (tester) async {
      // The screen and the core agreeing is the whole reason the check lives
      // in `commy_config` rather than being retyped here.
      await pumpScreen(tester);

      await tester.tap(find.text(t.dns.remote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), 'quic://9.9.9.9:853');
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      final server = DnsSectionBuilder.parseResolver(
        stored().remote,
        tag: 'dns-remote',
      );
      expect(server['type'], 'quic');
      expect(server['server'], '9.9.9.9');
      expect(server['server_port'], 853);
    });

    testWidgets('the reset button puts the default back', (tester) async {
      await pumpScreen(
        tester,
        dns: const DnsSettings(remote: 'udp://192.0.2.1'),
      );

      await tester.tap(find.text(t.dns.remote));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.dns.edit.reset));
      await tester.pumpAndSettle();

      expect(stored().remote, DnsSettings.defaultRemote);
    });
  });

  group('the cache switch', () {
    testWidgets("is the user's to set while FakeIP is off", (tester) async {
      await pumpScreen(tester);

      final control = tester.widget<CommySwitch>(
        find.byType(CommySwitch).last,
      );
      expect(control.onChanged, isNotNull);
      expect(find.text(t.dns.independentCacheHint), findsOneWidget);
    });

    testWidgets('follows FakeIP rather than lying about the configuration',
        (tester) async {
      // The builder emits `independentCache || fakeIp`, so a switch that sat
      // off here while FakeIP was on would be showing the user something the
      // generated configuration contradicts.
      await pumpScreen(
        tester,
        dns: const DnsSettings(fakeIp: true, independentCache: false),
      );

      final control = tester.widget<CommySwitch>(
        find.byType(CommySwitch).last,
      );
      expect(control.value, isTrue);
      expect(control.onChanged, isNull);
      expect(find.text(t.dns.independentCacheForced), findsOneWidget);
    });
  });
}
