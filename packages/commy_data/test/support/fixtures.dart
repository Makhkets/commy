import 'package:commy_domain/commy_domain.dart';

/// Real-shaped test data.
///
/// The credentials here are the *shape* of the real thing — a v4 uuid, a
/// Reality short id, a WireGuard private key, a panel URL with a token in the
/// path. Rule R2 and rule R3 are only meaningfully tested against values that
/// look like what they are meant to protect; a fixture that says `'secret'`
/// proves nothing about a regular expression.
///
/// None of these are live. They are random values generated for this file.
abstract final class Fixtures {
  /// A VLESS uuid.
  static const String uuid = '8f3c1e6a-9d2b-4c7f-a1e5-0b6d4a2c9f88';

  /// A Reality short id.
  static const String shortId = '7f3a2b1c9d8e6045';

  /// A Trojan password.
  static const String password = 'Tr0jan-P4ss.w0rd_2026';

  /// A WireGuard private key, base64, 32 bytes.
  static const String privateKey =
      'cOFA79Y8Ha0NfPq2VbT1u9kXmR4sZjLwEyGdIhCnBvA=';

  /// A subscription URL with the access token in the path.
  static final Uri subscriptionUrl = Uri.parse(
    'https://panel.example.com/sub/9f8e7d6c5b4a32100fedcba987654321?f=v2ray',
  );

  /// A Reality VLESS node with every kind of parameter on it.
  static ProxyNode vlessNode({
    String id = 'node-vless',
    String? subscriptionId,
    String? groupId,
    int sortIndex = 0,
  }) =>
      ProxyNode(
        id: id,
        name: 'Frankfurt Reality',
        protocol: Protocol.vless,
        host: 'de1.vpn.example.com',
        port: 443,
        subscriptionId: subscriptionId,
        groupId: groupId,
        countryCode: 'DE',
        sortIndex: sortIndex,
        params: const <String, Object?>{
          'uuid': uuid,
          'flow': 'xtls-rprx-vision',
          'security': 'reality',
          'sni': 'www.microsoft.com',
          'fp': 'chrome',
          'pbk': 'qGZKZkYcVJ9nWQ2mS4tHxD6fLpNrEoBwUvXaIyTsCmQ',
          'sid': shortId,
        },
      );

  /// A Trojan node whose only secret is a password.
  static ProxyNode trojanNode({
    String id = 'node-trojan',
    String? subscriptionId,
    int sortIndex = 0,
  }) =>
      ProxyNode(
        id: id,
        name: 'Amsterdam',
        protocol: Protocol.trojan,
        host: 'nl1.vpn.example.com',
        port: 8443,
        subscriptionId: subscriptionId,
        countryCode: 'NL',
        sortIndex: sortIndex,
        params: const <String, Object?>{
          'password': password,
          'sni': 'nl1.vpn.example.com',
          'alpn': 'h2,http/1.1',
        },
      );

  /// A SOCKS node with no credentials at all.
  static ProxyNode socksNode({String id = 'node-socks'}) => ProxyNode(
        id: id,
        name: 'Local debug',
        protocol: Protocol.socks,
        host: '127.0.0.1',
        port: 1080,
      );

  /// A subscription pointing at [subscriptionUrl].
  static Subscription subscription({
    String id = 'sub-1',
    Uri? url,
    int sortIndex = 0,
  }) =>
      Subscription(
        id: id,
        name: 'Example panel',
        url: url ?? subscriptionUrl,
        profileTitle: 'Example panel',
        updateIntervalHours: 12,
        autoUpdate: true,
        sortIndex: sortIndex,
        userInfo: SubscriptionUserInfo(
          upload: 1024,
          download: 2048,
          total: 107374182400,
          expire: DateTime.utc(2027),
        ),
      );
}
