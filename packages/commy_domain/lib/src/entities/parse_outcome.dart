import 'package:commy_domain/src/core/structural.dart';
import 'package:commy_domain/src/entities/import_failure.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';

/// What came out of parsing user input: the nodes, and what went wrong.
///
/// A parse never fails as a whole because part of the input was junk. Real
/// subscriptions contain duplicates and broken entries, and half a list must
/// not sink the import (docs/06-data-model.md, "Правила парсера").
class ParseOutcome {
  /// Creates an outcome.
  const ParseOutcome({
    this.nodes = const <ProxyNode>[],
    this.failures = const <ImportFailure>[],
  });

  /// An outcome with nothing in it.
  static const ParseOutcome empty = ParseOutcome();

  /// Everything that parsed.
  final List<ProxyNode> nodes;

  /// Everything that did not, with a reason attached.
  final List<ImportFailure> failures;

  /// Whether anything at all was imported.
  bool get hasNodes => nodes.isNotEmpty;

  /// Whether anything was skipped.
  bool get hasFailures => failures.isNotEmpty;

  /// Merges two outcomes, keeping the order of both.
  ParseOutcome merge(ParseOutcome other) => ParseOutcome(
        nodes: <ProxyNode>[...nodes, ...other.nodes],
        failures: <ImportFailure>[...failures, ...other.failures],
      );

  /// Returns a copy with the given fields replaced.
  ParseOutcome copyWith({
    List<ProxyNode>? nodes,
    List<ImportFailure>? failures,
  }) {
    return ParseOutcome(
      nodes: nodes ?? this.nodes,
      failures: failures ?? this.failures,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParseOutcome &&
          Structural.listEquals(other.nodes, nodes) &&
          Structural.listEquals(other.failures, failures);

  @override
  int get hashCode =>
      Object.hash(Structural.listHash(nodes), Structural.listHash(failures));

  @override
  String toString() =>
      'ParseOutcome(${nodes.length} nodes, ${failures.length} failures)';
}
