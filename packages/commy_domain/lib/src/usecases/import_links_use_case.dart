import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/node_duplicates.dart';
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
      final stored = NodeDuplicates.folded(assigned);
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
        CommyFailure.fromCaught(error, stackTrace),
      );
    }
  }
}
