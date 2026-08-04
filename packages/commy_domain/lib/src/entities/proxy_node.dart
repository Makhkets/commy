import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/core/redaction.dart';
import 'package:commy_domain/src/core/sentinel.dart';
import 'package:commy_domain/src/core/structural.dart';
import 'package:commy_domain/src/entities/protocol.dart';

/// One proxy server the user can route traffic through.
///
/// Protocol-specific fields are not modelled one by one: the set differs per
/// protocol and grows with every sing-box release. They live in [params]
/// instead — `uuid`, `flow`, `security`, `sni`, `fp`, `pbk`, `sid`, `alpn`,
/// `path`, `host`, `serviceName`, `method`, `password`, `obfs`, `congestion`
/// and whatever the next release adds.
///
/// Everything credential-like inside [params] is listed in [secretParamKeys]
/// and is blanked by [redacted] before a node reaches a log (rule R3). The
/// storage layer keeps those same keys out of the plain database (rule R2).
class ProxyNode {
  /// Creates a node.
  const ProxyNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.subscriptionId,
    this.groupId,
    this.countryCode,
    this.latency,
    this.lastCheckedAt,
    this.sortIndex = 0,
    this.params = const <String, Object?>{},
  });

  /// Restores a node from the map produced by [toJson].
  factory ProxyNode.fromJson(JsonMap json) => ProxyNode(
        id: JsonRead.string(json, 'id'),
        name: JsonRead.string(json, 'name'),
        protocol: Protocol.values.byName(JsonRead.string(json, 'protocol')),
        host: JsonRead.string(json, 'host'),
        port: JsonRead.integer(json, 'port'),
        subscriptionId: JsonRead.stringOrNull(json, 'subscriptionId'),
        groupId: JsonRead.stringOrNull(json, 'groupId'),
        countryCode: JsonRead.stringOrNull(json, 'countryCode'),
        latency: JsonRead.durationOrNull(json, 'latencyMicros'),
        lastCheckedAt: JsonRead.dateTimeOrNull(json, 'lastCheckedAt'),
        sortIndex: JsonRead.integerOr(json, 'sortIndex', orElse: 0),
        params: JsonRead.objectOrEmpty(json, 'params'),
      );

  /// Keys inside [params] that must never reach a log or an export.
  ///
  /// Lowercase, because matching is case-insensitive. Both the camelCase and
  /// the snake_case spelling of every key is listed: real subscriptions use
  /// whichever they feel like.
  static const Set<String> secretParamKeys = <String>{
    'auth',
    'auth_str',
    'authstr',
    'id',
    'obfs-password',
    'obfs_password',
    'obfspassword',
    'password',
    'peerpublickey',
    'pre_shared_key',
    'presharedkey',
    'private_key',
    'privatekey',
    'psk',
    'secret',
    'short_id',
    'shortid',
    'sid',
    'token',
    'uuid',
  };

  /// Stable identifier. Survives subscription updates where possible.
  final String id;

  /// Display name, as the panel wrote it.
  final String name;

  /// Wire protocol.
  final Protocol protocol;

  /// Server hostname or address.
  final String host;

  /// Server port.
  final int port;

  /// Subscription this node came from, or `null` when added by hand.
  final String? subscriptionId;

  /// Manual group this node belongs to, or `null`.
  final String? groupId;

  /// ISO 3166-1 alpha-2 country code, when it could be derived.
  final String? countryCode;

  /// Last measured round trip, or `null` when never measured.
  final Duration? latency;

  /// When [latency] was measured.
  final DateTime? lastCheckedAt;

  /// Position inside its subscription or group. Panels have an order; keep it.
  final int sortIndex;

  /// Protocol-specific fields. Never mutate the map in place.
  final Map<String, Object?> params;

  /// Reads a single protocol parameter as a string, or `null`.
  String? param(String key) {
    final value = params[key];
    return value == null ? null : '$value';
  }

  /// Whether this node came from a subscription rather than manual input.
  bool get isFromSubscription => subscriptionId != null;

  /// A copy safe to print: every secret in [params] is blanked.
  ///
  /// [host] and [port] survive on purpose — the live log view shows them and
  /// they are what makes a log useful. Exports must additionally replace them
  /// with [Redact.serverPlaceholder].
  ProxyNode redacted() => copyWith(
        params: Redact.params(params, secretParamKeys),
      );

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` explicitly to a nullable field clears it; omitting the
  /// argument keeps the current value.
  ProxyNode copyWith({
    String? id,
    String? name,
    Protocol? protocol,
    String? host,
    int? port,
    Object? subscriptionId = Sentinel.unset,
    Object? groupId = Sentinel.unset,
    Object? countryCode = Sentinel.unset,
    Object? latency = Sentinel.unset,
    Object? lastCheckedAt = Sentinel.unset,
    int? sortIndex,
    Map<String, Object?>? params,
  }) {
    return ProxyNode(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      subscriptionId: identical(subscriptionId, Sentinel.unset)
          ? this.subscriptionId
          : subscriptionId as String?,
      groupId: identical(groupId, Sentinel.unset)
          ? this.groupId
          : groupId as String?,
      countryCode: identical(countryCode, Sentinel.unset)
          ? this.countryCode
          : countryCode as String?,
      latency: identical(latency, Sentinel.unset)
          ? this.latency
          : latency as Duration?,
      lastCheckedAt: identical(lastCheckedAt, Sentinel.unset)
          ? this.lastCheckedAt
          : lastCheckedAt as DateTime?,
      sortIndex: sortIndex ?? this.sortIndex,
      params: params ?? this.params,
    );
  }

  /// Serialises the node, secrets included. Never write this to a plain store.
  JsonMap toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'subscriptionId': subscriptionId,
        'groupId': groupId,
        'countryCode': countryCode,
        'latencyMicros': latency?.inMicroseconds,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'sortIndex': sortIndex,
        'params': params,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyNode &&
          other.id == id &&
          other.name == name &&
          other.protocol == protocol &&
          other.host == host &&
          other.port == port &&
          other.subscriptionId == subscriptionId &&
          other.groupId == groupId &&
          other.countryCode == countryCode &&
          other.latency == latency &&
          other.lastCheckedAt == lastCheckedAt &&
          other.sortIndex == sortIndex &&
          Structural.mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        protocol,
        host,
        port,
        subscriptionId,
        groupId,
        countryCode,
        latency,
        lastCheckedAt,
        sortIndex,
        Structural.mapHash(params),
      );

  /// Never prints [params]: they hold credentials.
  @override
  String toString() => 'ProxyNode($id, ${protocol.name}, $name, $host:$port)';
}
