import 'package:commy_config/src/export/export_outcome.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/parsers/link_parser_registry.dart';
import 'package:commy_domain/commy_domain.dart';

/// Renders nodes back into share links.
///
/// The reverse of the parsers, and held to the same bar: what comes out has to
/// be readable by other clients, because "take your data with you" is only
/// true if the other end can read it (docs/06-data-model.md, "Экспорт").
class NodeLinkExporter {
  /// Creates an exporter over [registry].
  NodeLinkExporter({LinkParserRegistry? registry})
      : _registry = registry ?? LinkParserRegistry();

  final LinkParserRegistry _registry;

  /// Renders [node] as a link.
  Result<String, CommyFailure> toLink(ProxyNode node) {
    try {
      return Ok<String, CommyFailure>(_registry.toLink(node));
    } on LinkFormatException catch (error) {
      return Err<String, CommyFailure>(ConfigInvalidFailure(error.reason));
    } on Object catch (error, stackTrace) {
      return Err<String, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }

  /// Renders every node it can, dropping the rest with a reason.
  ExportOutcome toLinks(Iterable<ProxyNode> nodes) {
    final links = <String>[];
    final failures = <ImportFailure>[];
    for (final node in nodes) {
      final result = toLink(node);
      final link = result.valueOrNull;
      if (link != null) {
        links.add(link);
        continue;
      }
      final failure = result.failureOrNull;
      failures.add(
        ImportFailure(
          rawLine: '${node.name} (${node.protocol.wireName})',
          reason: failure is ConfigInvalidFailure
              ? failure.detail
              : 'Could not be exported',
        ),
      );
    }
    return ExportOutcome(links: links, failures: failures);
  }
}
