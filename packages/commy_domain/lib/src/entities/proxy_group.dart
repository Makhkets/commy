import 'package:commy_domain/src/core/structural.dart';

/// An outbound group inside the running core, as reported by it.
///
/// `Auto` is not a node but a group: it picks the best member and re-checks on
/// an interval (docs/05-ux-flows.md, scenario 4). Selecting inside a group is
/// what makes switching nodes possible without dropping the tunnel.
class ProxyGroup {
  /// Creates a group.
  const ProxyGroup({
    required this.tag,
    required this.type,
    this.now,
    this.all = const <String>[],
  });

  /// Tag of the group, as the core knows it.
  final String tag;

  /// Group kind reported by the core: `Selector`, `URLTest`, `Fallback`.
  final String type;

  /// Tag of the member currently in use, when the group has one.
  final String? now;

  /// Tags of every member, in the order the core lists them.
  final List<String> all;

  /// Whether the user can pick a member by hand.
  bool get isSelectable => type.toLowerCase() == 'selector';

  /// Returns a copy with the given fields replaced.
  ProxyGroup copyWith({
    String? tag,
    String? type,
    String? now,
    List<String>? all,
  }) {
    return ProxyGroup(
      tag: tag ?? this.tag,
      type: type ?? this.type,
      now: now ?? this.now,
      all: all ?? this.all,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyGroup &&
          other.tag == tag &&
          other.type == type &&
          other.now == now &&
          Structural.listEquals(other.all, all);

  @override
  int get hashCode => Object.hash(tag, type, now, Structural.listHash(all));

  @override
  String toString() => 'ProxyGroup($tag, $type, now: $now, ${all.length})';
}
