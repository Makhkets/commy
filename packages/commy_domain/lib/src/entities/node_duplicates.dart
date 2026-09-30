import 'package:commy_domain/src/entities/panel_notice.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';

/// Folds entries that name the same server into the single row they become.
///
/// A node's identity leaves the display name out on purpose, so one endpoint
/// listed in two of a panel's groups, or pasted twice under two names, is one
/// server and the store keeps one row for it.
///
/// The fold has two jobs and both want it applied before a write. A store
/// handed two entries under one primary key fails the whole insert, and the
/// user is told their subscription did not update when nothing was wrong with
/// it. A caller that reports the parser's list rather than the store's
/// promises servers that were never kept, and an import is reported once,
/// with no history to correct it afterwards.
///
/// ## Panel notices are not folded by identity
///
/// A [PanelNotice] is a line of text dressed as a server, and a panel that
/// has more than one line to say sends one entry per line, every one of them
/// on the same address that goes nowhere under the same placeholder
/// credential — Remnawave's remarks settings are lists of lines. The name is
/// the only thing that tells them apart, and it is exactly what the identity
/// leaves out, so folding them by id kept the last line — "Contact support" —
/// and threw away the one that said why.
///
/// So a notice whose id is already taken by a notice with *different* text
/// is given an id of its own: the same id with `~1`, `~2` … after it, counted
/// in the order the panel listed the lines. The first line keeps the id it
/// came with, so a panel that sends one line stores exactly what it did
/// before. The same text under the same id is still one row. Folding a
/// folded list changes nothing, which matters: the repository folds again.
abstract final class NodeDuplicates {
  /// What separates a notice's id from the number of its line.
  static const String _lineSeparator = '~';

  /// [nodes] with every repeated [ProxyNode.id] folded into one entry.
  ///
  /// The last entry wins the fields, the first keeps its place in the list —
  /// where storing the two of them one after another would have left them.
  /// Notices are kept apart by their text, as the class comment explains.
  ///
  /// The result is unmodifiable: callers read it and hand it on. Anything
  /// that needs to sort or extend the list copies it first.
  static List<ProxyNode> folded(List<ProxyNode> nodes) {
    final byId = <String, ProxyNode>{};
    final lineIds = <String, String>{};
    final linesPerId = <String, int>{};
    for (final node in nodes) {
      final kept = PanelNotice.isNotice(node)
          ? _apart(node, lineIds: lineIds, linesPerId: linesPerId)
          : node;
      byId[kept.id] = kept;
    }
    return List<ProxyNode>.unmodifiable(byId.values);
  }

  /// [notice] under the id its line of text is stored under.
  ///
  /// [lineIds] remembers which id each (id, text) pair was given, so a line
  /// the panel repeats lands on the row it already has; [linesPerId] counts
  /// the distinct lines seen under each id so far.
  static ProxyNode _apart(
    ProxyNode notice, {
    required Map<String, String> lineIds,
    required Map<String, int> linesPerId,
  }) {
    final line = '${notice.id}\n${notice.name.trim()}';
    final known = lineIds[line];
    if (known != null) {
      return known == notice.id ? notice : notice.copyWith(id: known);
    }
    final seen = linesPerId[notice.id] ?? 0;
    linesPerId[notice.id] = seen + 1;
    final id = seen == 0 ? notice.id : '${notice.id}$_lineSeparator$seen';
    lineIds[line] = id;
    return id == notice.id ? notice : notice.copyWith(id: id);
  }
}
