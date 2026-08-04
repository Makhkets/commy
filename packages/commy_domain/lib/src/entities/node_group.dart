import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/core/sentinel.dart';

/// A folder for nodes the user added by hand.
///
/// Subscriptions group their own nodes; this is the equivalent for links that
/// were pasted, scanned or opened from a file. Both render the same way on the
/// main screen (docs/05-ux-flows.md, scenario 4).
class NodeGroup {
  /// Creates a group.
  const NodeGroup({
    required this.id,
    required this.name,
    this.sortIndex = 0,
    this.isCollapsed = false,
    this.createdAt,
  });

  /// Restores a group from the map produced by [toJson].
  factory NodeGroup.fromJson(JsonMap json) => NodeGroup(
        id: JsonRead.string(json, 'id'),
        name: JsonRead.string(json, 'name'),
        sortIndex: JsonRead.integerOr(json, 'sortIndex', orElse: 0),
        isCollapsed: JsonRead.boolean(json, 'isCollapsed', orElse: false),
        createdAt: JsonRead.dateTimeOrNull(json, 'createdAt'),
      );

  /// Stable identifier.
  final String id;

  /// Display name.
  final String name;

  /// Position in the list on the main screen.
  final int sortIndex;

  /// Whether the group is folded away in the UI.
  final bool isCollapsed;

  /// When the group was created.
  final DateTime? createdAt;

  /// Returns a copy with the given fields replaced.
  NodeGroup copyWith({
    String? id,
    String? name,
    int? sortIndex,
    bool? isCollapsed,
    Object? createdAt = Sentinel.unset,
  }) {
    return NodeGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      sortIndex: sortIndex ?? this.sortIndex,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      createdAt: identical(createdAt, Sentinel.unset)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }

  /// Serialises the group.
  JsonMap toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'sortIndex': sortIndex,
        'isCollapsed': isCollapsed,
        'createdAt': createdAt?.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeGroup &&
          other.id == id &&
          other.name == name &&
          other.sortIndex == sortIndex &&
          other.isCollapsed == isCollapsed &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, name, sortIndex, isCollapsed, createdAt);

  @override
  String toString() => 'NodeGroup($id, $name)';
}
