import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// The local inbound: absent unless something needs it, and on loopback
/// unless the user asked for more.
void main() {
  const auth = LocalProxyAuth(password: '0123456789abcdef');

  List<Map<String, Object?>> build(
    AppSettings settings, {
    LocalProxyAuth? localAuth = auth,
  }) {
    return InboundSectionBuilder.build(
      settings: settings,
      routing: RoutingPolicy.defaults,
      platform: ConfigPlatform.android,
      localAuth: localAuth,
    );
  }

  group('InboundSectionBuilder', () {
    test('opens no local inbound unless something needs one', () {
      final tags = build(AppSettings.defaults).map((inbound) => inbound['tag']);

      expect(tags, <String>[SingBoxTags.tunInbound]);
    });

    test('the IP check gets a loopback inbound, not one on every interface',
        () {
      // Exception E-1: the app's own package is excluded from the TUN on
      // Android, so the check can only go through the tunnel by aiming at a
      // local port. A port open to the LAN would be a surface nobody asked for.
      final inbounds = build(
        const AppSettings(ipCheckUrl: 'https://ip.example/json'),
      );
      final mixed = inbounds.last;

      expect(inbounds, hasLength(2));
      expect(mixed['type'], SingBoxKeys.typeMixed);
      expect(mixed['tag'], SingBoxTags.mixedInbound);
      expect(mixed['listen'], InboundSectionBuilder.loopbackListenAddress);
      expect(mixed['listen_port'], AppSettings.defaultMixedPort);
    });

    test(
        'the loopback inbound asks for credentials, and is not opened '
        'without them', () {
      // Unauthenticated, any app on the phone could find it by scanning
      // localhost, and learn through it where the tunnel comes out.
      const settings = AppSettings(ipCheckUrl: 'https://ip.example/json');

      expect(build(settings).last['users'], <Map<String, Object?>>[
        <String, Object?>{'username': 'commy', 'password': '0123456789abcdef'},
      ]);
      expect(
        build(settings, localAuth: null).map((inbound) => inbound['tag']),
        <String>[SingBoxTags.tunInbound],
      );
    });

    test('sharing with the LAN opens the same port on every interface', () {
      final mixed = build(const AppSettings(allowLan: true)).last;

      expect(mixed['listen'], InboundSectionBuilder.lanListenAddress);
      // The user shares it on purpose; the devices they share it with have
      // no way to know a password the app made up.
      expect(mixed.containsKey('users'), isFalse);
      expect(
        build(const AppSettings(allowLan: true), localAuth: null)
            .last['listen'],
        InboundSectionBuilder.lanListenAddress,
      );
    });

    test('with both on, the LAN address wins and there is still one inbound',
        () {
      final inbounds = build(
        const AppSettings(
          allowLan: true,
          ipCheckUrl: 'https://ip.example/json',
        ),
      );

      expect(inbounds, hasLength(2));
      expect(inbounds.last['listen'], InboundSectionBuilder.lanListenAddress);
    });
  });
}
