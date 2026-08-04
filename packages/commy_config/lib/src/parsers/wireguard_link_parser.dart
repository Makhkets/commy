import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `wireguard://` and `wg://` links.
///
/// ```text
/// wireguard://<private-key>@host:51820?publickey=..&presharedkey=..
///            &address=10.0.0.2/32&mtu=1420&reserved=0,0,0#name
/// ```
///
/// There is no standard for this scheme, so the parser accepts every spelling
/// of every field that clients have shipped. What it will not do is guess a
/// missing peer public key or a missing local address: without either of them
/// the tunnel cannot come up, and a node that silently fails later is worse
/// than an import error now.
class WireguardLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const WireguardLinkParser();

  /// Query keys that may hold the peer public key.
  static const List<String> publicKeyKeys = <String>[
    'publickey',
    'public-key',
    'public_key',
    'peerpublickey',
    'peer_public_key',
    'pbk',
  ];

  /// Query keys that may hold the pre-shared key.
  static const List<String> preSharedKeyKeys = <String>[
    'presharedkey',
    'pre-shared-key',
    'pre_shared_key',
    'psk',
  ];

  /// Query keys that may hold the local interface addresses.
  static const List<String> addressKeys = <String>[
    'address',
    'addresses',
    'ip',
    'local_address',
    'localaddress',
  ];

  /// Query keys that may hold the private key when it is not in the user info.
  static const List<String> privateKeyKeys = <String>[
    'privatekey',
    'private-key',
    'private_key',
    'secretkey',
  ];

  /// Query keys that may hold the keepalive interval, in seconds.
  static const List<String> keepAliveKeys = <String>[
    'keepalive',
    'persistentkeepalive',
    'persistent_keepalive',
  ];

  @override
  Set<String> get schemes => const <String>{'wireguard', 'wg'};

  @override
  Protocol get protocol => Protocol.wireguard;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || !schemes.contains(link.scheme)) {
      throw const LinkFormatException('Not a wireguard:// link');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException(
        'wireguard:// link carries no server port',
      );
    }
    final privateKey = link.decodedUserInfo.trim().isNotEmpty
        ? link.decodedUserInfo.trim()
        : link.query.firstOf(privateKeyKeys);
    if (privateKey == null || privateKey.isEmpty) {
      throw const LinkFormatException(
        'wireguard:// link carries no private key',
      );
    }
    final peerPublicKey = link.query.firstOf(publicKeyKeys);
    if (peerPublicKey == null || peerPublicKey.isEmpty) {
      throw const LinkFormatException(
        'wireguard:// link carries no peer public key',
      );
    }
    final addresses = link.query.csvOf(addressKeys);
    if (addresses.isEmpty) {
      throw const LinkFormatException(
        'wireguard:// link carries no local address',
      );
    }
    final reserved = link.query.csv('reserved');
    return NodeFactory.build(
      protocol: Protocol.wireguard,
      name: link.name,
      host: link.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.privateKey: privateKey,
        ParamKeys.peerPublicKey: peerPublicKey,
        ParamKeys.preSharedKey: link.query.firstOf(preSharedKeyKeys),
        ParamKeys.localAddress: addresses.join(','),
        ParamKeys.reserved: reserved.isEmpty ? null : reserved.join(','),
        ParamKeys.mtu: link.query.integer('mtu'),
        ParamKeys.keepAlive: link.query.integerOf(keepAliveKeys),
      },
    );
  }

  @override
  String toLink(ProxyNode node) {
    final privateKey = node.param(ParamKeys.privateKey);
    final peerPublicKey = node.param(ParamKeys.peerPublicKey);
    if (privateKey == null || privateKey.isEmpty) {
      throw const LinkFormatException('Node carries no private key');
    }
    if (peerPublicKey == null || peerPublicKey.isEmpty) {
      throw const LinkFormatException('Node carries no peer public key');
    }
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final entries = <MapEntry<String, String>>[
      MapEntry<String, String>('publickey', peerPublicKey),
    ];
    void add(String key, String? value) {
      if (value != null && value.isNotEmpty) {
        entries.add(MapEntry<String, String>(key, value));
      }
    }

    add('presharedkey', node.param(ParamKeys.preSharedKey));
    add('address', node.param(ParamKeys.localAddress));
    add('reserved', node.param(ParamKeys.reserved));
    add('mtu', node.param(ParamKeys.mtu));
    add('keepalive', node.param(ParamKeys.keepAlive));
    final query = entries
        .map((e) => '${e.key}=${Percent.encodeQueryValue(e.value)}')
        .join('&');
    return 'wireguard://${Percent.encode(privateKey)}@$address:${node.port}'
        '?$query#${Percent.encodeFragment(node.name)}';
  }
}
