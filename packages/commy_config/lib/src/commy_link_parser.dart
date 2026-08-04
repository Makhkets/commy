import 'package:commy_config/src/export/node_link_exporter.dart';
import 'package:commy_config/src/parsers/link_parser_registry.dart';
import 'package:commy_config/src/subscription/subscription_body_reader.dart';
import 'package:commy_domain/commy_domain.dart';

/// The domain's `LinkParser`, backed by the registry and the body reader.
///
/// One entry point for everything the user can paste: a single link, a list of
/// them, that list base64 wrapped, a Clash document or a sing-box one. The
/// contract is the domain's: `Err` only when the input as a whole made no
/// sense, and a document with some broken entries is a success with failures
/// attached (docs/02-architecture.md, step 2).
class CommyLinkParser implements LinkParser {
  /// Creates a parser.
  CommyLinkParser({
    LinkParserRegistry? registry,
    SubscriptionBodyReader? reader,
    NodeLinkExporter? exporter,
  })  : _registry = registry ?? LinkParserRegistry(),
        _givenReader = reader,
        _givenExporter = exporter;

  final LinkParserRegistry _registry;
  final SubscriptionBodyReader? _givenReader;
  final NodeLinkExporter? _givenExporter;

  /// The body reader, built from the registry when none was injected.
  late final SubscriptionBodyReader reader =
      _givenReader ?? SubscriptionBodyReader(registry: _registry);

  /// The exporter, built from the registry when none was injected.
  late final NodeLinkExporter exporter =
      _givenExporter ?? NodeLinkExporter(registry: _registry);

  @override
  Result<ParseOutcome, CommyFailure> parse(String input) {
    try {
      final outcome = reader.read(input);
      if (!outcome.hasNodes && outcome.hasFailures) {
        return Err<ParseOutcome, CommyFailure>(
          SubscriptionMalformedFailure(outcome.failures.first.reason),
        );
      }
      return Ok<ParseOutcome, CommyFailure>(outcome);
    } on Object catch (error, stackTrace) {
      return Err<ParseOutcome, CommyFailure>(
        UnknownFailure(error, stackTrace),
      );
    }
  }

  @override
  bool canParse(String input) {
    try {
      return reader.canRead(input);
    } on Object catch (_) {
      return false;
    }
  }

  @override
  Result<String, CommyFailure> toLink(ProxyNode node) => exporter.toLink(node);
}
