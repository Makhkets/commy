import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Row ⇄ `NodeGroup`. Nothing sensitive on either side.
abstract final class NodeGroupMapper {
  /// Builds a domain group out of a row.
  static NodeGroup toDomain(NodeGroupRow row) => NodeGroup(
        id: row.id,
        name: row.name,
        sortIndex: row.sortIndex,
        isCollapsed: row.isCollapsed,
        createdAt: row.createdAt,
      );

  /// Builds the row half of [group].
  static NodeGroupRowsCompanion toCompanion(NodeGroup group) =>
      NodeGroupRowsCompanion(
        id: Value<String>(group.id),
        name: Value<String>(group.name),
        sortIndex: Value<int>(group.sortIndex),
        isCollapsed: Value<bool>(group.isCollapsed),
        createdAt: Value<DateTime?>(group.createdAt),
      );
}
