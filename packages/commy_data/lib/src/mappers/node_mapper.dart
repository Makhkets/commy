import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/secure/node_secret_parts.dart';
import 'package:commy_data/src/secure/secret_keys.dart';
import 'package:commy_data/src/util/json_text.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Row ⇄ `ProxyNode`, with the credential split baked in.
///
/// The only two functions in the package that know how a node is torn apart
/// for storage and put back together for use. Keeping both here means the split
/// cannot drift apart — a bug that would show up as a node that connects fine
/// until the app restarts.
abstract final class NodeMapper {
  /// Fallback protocol for a row whose `protocol` column is unreadable.
  ///
  /// Should be unreachable: the column is only ever written from
  /// `Protocol.name`. A row that survived a botched hand-edit still renders as
  /// something the user can delete, instead of taking the whole list down.
  static const Protocol fallbackProtocol = Protocol.vless;

  /// Builds a domain node out of a row and its credentials.
  ///
  /// [secretParams] comes from `SecretVault`; an empty map means the node has
  /// no secrets or that they could not be read, and the difference is visible
  /// downstream: a config built without a uuid fails validation loudly in
  /// `ConfigGenerator` rather than silently connecting to nothing.
  static ProxyNode toDomain(
    NodeRow row, {
    Map<String, Object?> secretParams = const <String, Object?>{},
  }) {
    return ProxyNode(
      id: row.id,
      name: row.name,
      protocol: Protocol.fromWireName(row.protocol) ??
          _byEnumName(row.protocol) ??
          fallbackProtocol,
      host: row.host,
      port: row.port,
      subscriptionId: row.subscriptionId,
      groupId: row.groupId,
      countryCode: row.countryCode,
      latency: row.latencyMicros == null
          ? null
          : Duration(microseconds: row.latencyMicros!),
      lastCheckedAt: row.lastCheckedAt,
      sortIndex: row.sortIndex,
      params: NodeSecretParts.merge(
        JsonText.decodeOrEmpty(row.publicParamsJson),
        secretParams,
      ),
    );
  }

  /// Builds the row half of [node]. The credentials are *not* in the result.
  ///
  /// Use together with [secretsOf]; writing one without the other leaves a node
  /// that cannot connect.
  static NodeRowsCompanion toCompanion(ProxyNode node) {
    final parts = NodeSecretParts.of(node.params);
    return NodeRowsCompanion(
      id: Value<String>(node.id),
      name: Value<String>(node.name),
      protocol: Value<String>(node.protocol.name),
      host: Value<String>(node.host),
      port: Value<int>(node.port),
      subscriptionId: Value<String?>(node.subscriptionId),
      groupId: Value<String?>(node.groupId),
      countryCode: Value<String?>(node.countryCode),
      latencyMicros: Value<int?>(node.latency?.inMicroseconds),
      lastCheckedAt: Value<DateTime?>(node.lastCheckedAt),
      sortIndex: Value<int>(node.sortIndex),
      publicParamsJson: Value<String>(JsonText.encode(parts.public)),
      secretRef: Value<String?>(
        parts.hasSecret ? SecretKeys.nodeParams(node.id) : null,
      ),
    );
  }

  /// The credential half of [node], destined for the secure store.
  static Map<String, Object?> secretsOf(ProxyNode node) =>
      NodeSecretParts.of(node.params).secret;

  /// Identity of a node for the purposes of a subscription refresh.
  ///
  /// Two nodes with the same protocol, host and port are "the same server" even
  /// when the panel renamed or reordered them, so the local id — and with it
  /// the latency history and the current selection — is carried over
  /// (`NodeRepository.replaceForSubscription`).
  static String endpointKey(Protocol protocol, String host, int port) =>
      '${protocol.name}|${host.toLowerCase()}|$port';

  /// [endpointKey] of an already built node.
  static String endpointKeyOf(ProxyNode node) =>
      endpointKey(node.protocol, node.host, node.port);

  /// [endpointKey] of a stored row.
  static String endpointKeyOfRow(NodeRow row) => endpointKey(
        Protocol.fromWireName(row.protocol) ??
            _byEnumName(row.protocol) ??
            fallbackProtocol,
        row.host,
        row.port,
      );

  static Protocol? _byEnumName(String name) {
    for (final protocol in Protocol.values) {
      if (protocol.name == name) {
        return protocol;
      }
    }
    return null;
  }
}
