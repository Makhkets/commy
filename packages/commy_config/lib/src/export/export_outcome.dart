import 'package:commy_domain/commy_domain.dart';

/// What came out of rendering a list of nodes back into links.
///
/// Partial success is success, the same way it is on the import side: forty
/// links out of fifty beats refusing to export because one node uses a
/// protocol with no agreed share format.
class ExportOutcome {
  /// Creates an outcome.
  const ExportOutcome({
    this.links = const <String>[],
    this.failures = const <ImportFailure>[],
  });

  /// An outcome with nothing in it.
  static const ExportOutcome empty = ExportOutcome();

  /// Everything that rendered, in the order the nodes were given.
  final List<String> links;

  /// Everything that did not, with a reason attached.
  final List<ImportFailure> failures;

  /// The links as a newline separated document.
  String get document => links.join('\n');

  /// Whether anything rendered.
  bool get hasLinks => links.isNotEmpty;

  /// Whether anything failed to render.
  bool get hasFailures => failures.isNotEmpty;

  @override
  String toString() =>
      'ExportOutcome(${links.length} links, ${failures.length} failures)';
}
