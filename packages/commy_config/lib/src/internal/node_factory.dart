import 'package:commy_config/src/internal/node_id_factory.dart';
import 'package:commy_domain/commy_domain.dart';

/// Assembles a [ProxyNode] from what a parser managed to extract.
///
/// Every parser goes through here so that three things hold everywhere:
/// empty parameters are dropped rather than stored as `''`, the parameter map
/// is key-sorted so the output is byte-stable, and the identifier is derived
/// the same way for every protocol.
abstract final class NodeFactory {
  /// Builds a node, cleaning [params] and deriving the identifier.
  ///
  /// [name] falls back to `host:port` when the link carried no fragment.
  static ProxyNode build({
    required Protocol protocol,
    required String name,
    required String host,
    required int port,
    Map<String, Object?> params = const <String, Object?>{},
    String? subscriptionId,
    String? groupId,
    int sortIndex = 0,
  }) {
    final cleaned = clean(params);
    return ProxyNode(
      id: NodeIdFactory.forNode(
        protocol: protocol,
        host: host,
        port: port,
        params: cleaned,
      ),
      name: name.trim().isEmpty ? '$host:$port' : name.trim(),
      protocol: protocol,
      host: host,
      port: port,
      subscriptionId: subscriptionId,
      groupId: groupId,
      sortIndex: sortIndex,
      params: cleaned,
    );
  }

  /// Drops empty values from [params] and sorts what is left by key.
  ///
  /// `null`, blank strings, empty lists and `false` all mean "the link did
  /// not say", and storing them would make two identical nodes compare
  /// unequal depending on which panel wrote the link.
  static Map<String, Object?> clean(Map<String, Object?> params) {
    final kept = <String, Object?>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.trim().isEmpty) {
        continue;
      }
      if (value is bool && !value) {
        continue;
      }
      if (value is List<Object?> && value.isEmpty) {
        continue;
      }
      kept[entry.key] = value is String ? value.trim() : value;
    }
    final keys = kept.keys.toList()..sort();
    return <String, Object?>{for (final key in keys) key: kept[key]};
  }
}
