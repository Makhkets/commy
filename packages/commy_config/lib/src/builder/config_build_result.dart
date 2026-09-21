import 'package:commy_config/src/builder/left_out_node.dart';
import 'package:commy_domain/commy_domain.dart';

/// A built configuration plus everything the builder had to leave out.
///
/// The warnings are not errors: a rule that names a rule set nobody downloaded
/// is dropped so the tunnel still comes up, but the user has to be told, or
/// they are left wondering why their rule does nothing.
class ConfigBuildResult {
  /// Creates a result.
  const ConfigBuildResult({
    required this.config,
    this.warnings = const <String>[],
    this.leftOut = const <LeftOutNode>[],
  });

  /// The configuration, ready for the core.
  final CoreConfig config;

  /// Human readable notes about what was dropped and why.
  final List<String> warnings;

  /// Servers that could not be expressed and are not in the document.
  ///
  /// Never the selected one: a document without the server the user asked for
  /// is not a result, it is a failure, and it is reported as one.
  final List<LeftOutNode> leftOut;

  /// Whether anything was dropped.
  bool get hasWarnings => warnings.isNotEmpty;

  /// Never prints the configuration: it holds every credential in the clear.
  @override
  String toString() => 'ConfigBuildResult(${warnings.length} warnings, '
      '${leftOut.length} left out)';
}
