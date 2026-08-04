import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/http_link_parser.dart';
import 'package:commy_config/src/parsers/hysteria2_link_parser.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_config/src/parsers/shadowsocks_link_parser.dart';
import 'package:commy_config/src/parsers/shadowtls_link_parser.dart';
import 'package:commy_config/src/parsers/socks_link_parser.dart';
import 'package:commy_config/src/parsers/trojan_link_parser.dart';
import 'package:commy_config/src/parsers/tuic_link_parser.dart';
import 'package:commy_config/src/parsers/vless_link_parser.dart';
import 'package:commy_config/src/parsers/vmess_link_parser.dart';
import 'package:commy_config/src/parsers/wireguard_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Dispatches a link to the parser that owns its scheme.
///
/// Also owns the only place that turns a thrown `LinkFormatException` into an
/// [ImportFailure]: half a list of nodes must not sink an import, so a broken
/// entry becomes a line the user can read rather than an exception
/// (docs/06-data-model.md, "Правила парсера").
class LinkParserRegistry {
  /// Creates a registry over [parsers].
  LinkParserRegistry({List<NodeLinkParser> parsers = defaultParsers})
      : _parsers = parsers,
        _byScheme = <String, NodeLinkParser>{
          for (final parser in parsers)
            for (final scheme in parser.schemes) scheme: parser,
        };

  /// Every parser the package ships, in a fixed order.
  static const List<NodeLinkParser> defaultParsers = <NodeLinkParser>[
    VlessLinkParser(),
    VmessLinkParser(),
    TrojanLinkParser(),
    ShadowsocksLinkParser(),
    Hysteria2LinkParser(),
    TuicLinkParser(),
    WireguardLinkParser(),
    ShadowtlsLinkParser(),
    SocksLinkParser(),
    HttpLinkParser(),
  ];

  /// Prefixes that mark a line in a subscription as a comment.
  static const List<String> commentPrefixes = <String>['#', '//', ';'];

  /// The UTF-8 byte order mark, which panels do leave at the top of a body.
  static const String byteOrderMark = '\u{FEFF}';

  final List<NodeLinkParser> _parsers;
  final Map<String, NodeLinkParser> _byScheme;

  /// Every scheme that resolves to a parser.
  Set<String> get knownSchemes => _byScheme.keys.toSet();

  /// The parsers in registration order.
  List<NodeLinkParser> get parsers => List<NodeLinkParser>.unmodifiable(
        _parsers,
      );

  /// The parser registered for [scheme], or `null`.
  NodeLinkParser? forScheme(String scheme) =>
      _byScheme[scheme.toLowerCase().replaceAll(RegExp('[:/]'), '')];

  /// The parser that produces [protocol], or `null`.
  NodeLinkParser? forProtocol(Protocol protocol) {
    for (final parser in _parsers) {
      if (parser.protocol == protocol) {
        return parser;
      }
    }
    return null;
  }

  /// Whether [raw] starts with a scheme we can read.
  bool canParse(String raw) {
    final scheme = RawLink.schemeOf(raw);
    if (scheme == null) {
      return false;
    }
    if (!_byScheme.containsKey(scheme)) {
      return false;
    }
    if (scheme == 'http' || scheme == 'https') {
      return HttpLinkParser.looksLikeProxy(raw);
    }
    return true;
  }

  /// Parses one link, throwing `LinkFormatException` when it cannot.
  ProxyNode parse(String raw) {
    final scheme = RawLink.schemeOf(raw);
    if (scheme == null) {
      throw const LinkFormatException('Not a proxy link');
    }
    final parser = _byScheme[scheme];
    if (parser == null) {
      throw LinkFormatException('Unsupported scheme "$scheme://"');
    }
    final isWebScheme = scheme == 'http' || scheme == 'https';
    if (isWebScheme && !HttpLinkParser.looksLikeProxy(raw)) {
      throw const LinkFormatException(
        'Looks like a subscription address, not a proxy',
      );
    }
    return parser.parse(raw);
  }

  /// Renders [node] back into a link, throwing when the protocol has no form.
  String toLink(ProxyNode node) {
    final parser = forProtocol(node.protocol);
    if (parser == null) {
      throw LinkFormatException(
        'No share link format for ${node.protocol.wireName}',
      );
    }
    return parser.toLink(node);
  }

  /// Parses a newline separated list of links.
  ///
  /// Blank lines and comments are skipped silently; everything else either
  /// becomes a node or becomes an [ImportFailure] with a readable reason.
  ParseOutcome parseLines(
    String input, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final nodes = <ProxyNode>[];
    final failures = <ImportFailure>[];
    var index = startIndex;
    for (final rawLine in _split(input)) {
      final line = rawLine.trim();
      if (line.isEmpty || _isComment(line)) {
        continue;
      }
      if (!RawLink.hasScheme(line)) {
        failures.add(
          ImportFailure(rawLine: line, reason: 'Line is not a proxy link'),
        );
        continue;
      }
      try {
        final node = parse(line);
        nodes.add(
          node.copyWith(
            subscriptionId: subscriptionId,
            groupId: groupId,
            sortIndex: index,
          ),
        );
        index++;
      } on LinkFormatException catch (error) {
        failures.add(ImportFailure(rawLine: line, reason: error.reason));
      } on Object catch (error) {
        failures.add(
          ImportFailure(rawLine: line, reason: 'Could not be read: $error'),
        );
      }
    }
    return ParseOutcome(nodes: nodes, failures: failures);
  }

  static bool _isComment(String line) {
    for (final prefix in commentPrefixes) {
      if (line.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  static List<String> _split(String input) {
    final withoutBom =
        input.startsWith(byteOrderMark) ? input.substring(1) : input;
    return withoutBom.split(RegExp(r'[\r\n]+'));
  }
}
