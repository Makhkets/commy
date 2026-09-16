import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/ports/link_parser.dart';
import 'package:commy_domain/src/ports/node_repository.dart';

/// Imports pasted, scanned or opened input as manually added nodes.
///
/// Partial success is success: whatever parsed is stored, whatever did not is
/// returned with a reason so the user can see the list.
///
/// The outcome it returns describes the store, not the parser: its nodes are
/// the rows the import left behind. Callers report that number to the user.
class ImportLinksUseCase {
  /// Creates the use case.
  const ImportLinksUseCase({required this.parser, required this.nodes});

  /// What turns text into nodes.
  final LinkParser parser;

  /// Where the nodes are stored.
  final NodeRepository nodes;

  /// Parses [input] and stores everything that came out of it.
  ///
  /// [groupId] puts the imported nodes into a manual group; `null` leaves them
  /// ungrouped.
  ///
  /// The returned outcome carries one node per stored row: two links naming
  /// the same server collapse into the one row they become, and the skipped
  /// lines pass through untouched.
  Future<Result<ParseOutcome, CommyFailure>> call(
    String input, {
    String? groupId,
  }) async {
    try {
      final parsed = parser.parse(input);
      final parseFailure = parsed.failureOrNull;
      if (parseFailure != null) {
        return Err<ParseOutcome, CommyFailure>(parseFailure);
      }
      final outcome = parsed.valueOrNull ?? ParseOutcome.empty;
      if (!outcome.hasNodes) {
        return Ok<ParseOutcome, CommyFailure>(outcome);
      }

      final assigned = <ProxyNode>[
        for (final node in outcome.nodes) node.copyWith(groupId: groupId),
      ];
      final stored = _collapseDuplicates(assigned);
      final saved = await nodes.upsertAll(stored);
      final saveFailure = saved.failureOrNull;
      if (saveFailure != null) {
        return Err<ParseOutcome, CommyFailure>(saveFailure);
      }
      return Ok<ParseOutcome, CommyFailure>(
        outcome.copyWith(nodes: stored),
      );
    } on Object catch (error, stackTrace) {
      return Err<ParseOutcome, CommyFailure>(
        UnknownFailure(error, stackTrace),
      );
    }
  }

  /// Folds entries that name the same server into the single row they become.
  ///
  /// A node's identity leaves the display name out on purpose, so two links
  /// that differ only by name are one server and the store holds one row for
  /// them. Handing the caller the parser's list would therefore promise two
  /// servers where one was stored, and an import is reported once with no
  /// history to correct it afterwards.
  ///
  /// The later entry wins the fields, the earlier one its place in the list,
  /// which is what a store that upserts does anyway: importing "A then B" in
  /// one go leaves what importing A and then B separately would.
  static List<ProxyNode> _collapseDuplicates(List<ProxyNode> nodes) {
    final byId = <String, ProxyNode>{};
    for (final node in nodes) {
      byId[node.id] = node;
    }
    return List<ProxyNode>.unmodifiable(byId.values);
  }
}
