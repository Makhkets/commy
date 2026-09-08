import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// The local inbound: absent unless something needs it, and on loopback
/// unless the user asked for more.
void main() {
  List<Map<String, Object?>> build(AppSettings settings) {
    return InboundSectionBuilder.build(
      settings: settings,
      routing: RoutingPolicy.defaults,
      platform: ConfigPlatform.android,
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

    test('sharing with the LAN opens the same port on every interface', () {
      final mixed = build(const AppSettings(allowLan: true)).last;

      expect(mixed['listen'], InboundSectionBuilder.lanListenAddress);
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
