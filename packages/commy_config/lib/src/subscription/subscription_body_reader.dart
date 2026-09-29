import 'dart:convert';

import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/map_read.dart';
import 'package:commy_config/src/parsers/link_parser_registry.dart';
import 'package:commy_config/src/subscription/clash_proxy_reader.dart';
import 'package:commy_config/src/subscription/clash_yaml_reader.dart';
import 'package:commy_config/src/subscription/sing_box_outbound_reader.dart';
import 'package:commy_domain/commy_domain.dart';

/// Works out what a subscription body is and turns it into nodes.
///
/// The detection order is the one in docs/06-data-model.md, "Определение
/// формата", ordered by how often a real panel serves it:
///
/// 1. a list of protocol links, one per line;
/// 2. the same list, base64 wrapped — what Marzban, Remnawave and x-ui do by
///    default;
/// 3. a sing-box or Xray JSON document, read from `outbounds` (and, for
///    sing-box 1.11 and later, `endpoints`, where WireGuard lives);
/// 4. a Clash or Clash.Meta YAML document, read from `proxies`;
/// 5. a bare JSON array of node objects, or of whole Xray configurations —
///    the Xray JSON subscription of Marzban, Remnawave and 3x-ui.
///
/// The first format that yields at least one node wins. A format that yields
/// nothing but failures is not a match: a Clash file with one broken entry
/// must not be reported as "not a Clash file".
class SubscriptionBodyReader {
  /// Creates a reader over [registry].
  SubscriptionBodyReader({LinkParserRegistry? registry})
      : _registry = registry ?? LinkParserRegistry();

  /// How many times a body may be base64 wrapped before we stop unwrapping.
  ///
  /// Two happens in the wild — a panel base64-wrapping an already wrapped
  /// upstream. Beyond that it is a loop, not a subscription.
  static const int maxUnwrapDepth = 3;

  /// The UTF-8 byte order mark, which panels do leave at the top of a body.
  static const String byteOrderMark = '\u{FEFF}';

  final LinkParserRegistry _registry;

  /// The parser registry this reader dispatches links to.
  LinkParserRegistry get registry => _registry;

  /// Whether [body] looks like something [read] can make sense of.
  ///
  /// Cheap on purpose: this is what lights up the paste button when the
  /// clipboard changes, so it must not parse the whole document.
  bool canRead(String body, {int depth = 0}) {
    final trimmed = _strip(body);
    if (trimmed.isEmpty) {
      return false;
    }
    if (_hasAnyLink(trimmed)) {
      return true;
    }
    if (ClashYamlReader.looksLikeClash(trimmed)) {
      return true;
    }
    if (_looksLikeJson(trimmed)) {
      return true;
    }
    if (depth >= maxUnwrapDepth) {
      return false;
    }
    final decoded = LenientBase64.decodeToString(trimmed);
    if (decoded == null || decoded.trim() == trimmed) {
      return false;
    }
    return canRead(decoded, depth: depth + 1);
  }

  /// Reads [body] into nodes and the reasons for whatever was skipped.
  ///
  /// [subscriptionId] and [groupId] are stamped on every node produced, and
  /// [startIndex] seeds `sortIndex` so a panel's own order survives.
  ParseOutcome read(
    String body, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
    int depth = 0,
  }) {
    final trimmed = _strip(body);
    if (trimmed.isEmpty) {
      return const ParseOutcome(
        failures: <ImportFailure>[
          ImportFailure(rawLine: '', reason: 'The body is empty'),
        ],
      );
    }

    final links = _registry.parseLines(
      trimmed,
      subscriptionId: subscriptionId,
      groupId: groupId,
      startIndex: startIndex,
    );
    if (links.hasNodes) {
      return links;
    }

    if (depth < maxUnwrapDepth) {
      final decoded = LenientBase64.decodeToString(trimmed);
      if (decoded != null && decoded.trim() != trimmed) {
        final unwrapped = read(
          decoded,
          subscriptionId: subscriptionId,
          groupId: groupId,
          startIndex: startIndex,
          depth: depth + 1,
        );
        if (unwrapped.hasNodes) {
          return unwrapped;
        }
      }
    }

    if (_looksLikeJson(trimmed)) {
      final fromJson = readJson(
        trimmed,
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      );
      if (fromJson != null && fromJson.hasNodes) {
        return fromJson;
      }
      if (fromJson != null && fromJson.hasFailures) {
        return fromJson;
      }
    }

    if (ClashYamlReader.looksLikeClash(trimmed)) {
      final fromClash = readClash(
        trimmed,
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      );
      if (fromClash != null) {
        return fromClash;
      }
    }

    if (links.hasFailures) {
      return links;
    }
    return const ParseOutcome(
      failures: <ImportFailure>[
        ImportFailure(
          rawLine: '',
          reason: 'This is not a link list, a Clash file or a sing-box config',
        ),
      ],
    );
  }

  /// Reads a JSON document, or returns `null` when it is not valid JSON.
  ///
  /// Understands four shapes: a sing-box or Xray configuration with an
  /// `outbounds` array, a Clash document rendered as JSON with a `proxies`
  /// array, a bare array of node objects or link strings, and an array of
  /// whole Xray configurations, one per server.
  ParseOutcome? readJson(
    String body, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is List) {
      return _readArray(
        decoded,
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      );
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final fromDocument = _readDocument(
      decoded,
      subscriptionId: subscriptionId,
      groupId: groupId,
      startIndex: startIndex,
    );
    if (fromDocument != null) {
      return fromDocument;
    }
    final proxies = MapRead.objectList(decoded, <String>['proxies']);
    if (proxies.isNotEmpty) {
      return _readEntries(
        proxies,
        const <String>[],
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      );
    }
    // A single node object is a shape people do paste.
    if (SingBoxOutboundReader.looksLikeServer(decoded)) {
      return _readEntries(
        <Map<String, Object?>>[decoded],
        const <String>[],
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      );
    }
    return null;
  }

  /// Reads a Clash YAML document, or returns `null` when it is not one.
  ParseOutcome? readClash(
    String body, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final document = ClashYamlReader.tryParseDocument(body);
    if (document == null) {
      return null;
    }
    final proxies = MapRead.objectList(document, <String>['proxies']);
    if (proxies.isEmpty) {
      return null;
    }
    return _readEntries(
      proxies,
      const <String>[],
      subscriptionId: subscriptionId,
      groupId: groupId,
      startIndex: startIndex,
    );
  }

  /// Reads a top-level JSON array.
  ///
  /// Usually its elements are nodes or links. An Xray JSON subscription
  /// (Marzban's `v2ray-json`, Remnawave's XRAY_JSON, 3x-ui's JSON
  /// subscription) is instead an array of whole configurations, one per
  /// server, each with its own `outbounds`: those are read as documents, in
  /// order, so the panel's order survives.
  ParseOutcome _readArray(
    List<Object?> array, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final objects = _asObjects(array);
    if (!objects.any(_isDocument)) {
      return _readEntries(
        objects,
        _plainStrings(array),
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      );
    }
    var outcome = ParseOutcome.empty;
    var index = startIndex;
    for (final object in objects) {
      final part = _readDocument(
            object,
            subscriptionId: subscriptionId,
            groupId: groupId,
            startIndex: index,
          ) ??
          _readEntries(
            <Map<String, Object?>>[object],
            const <String>[],
            subscriptionId: subscriptionId,
            groupId: groupId,
            startIndex: index,
          );
      outcome = outcome.merge(part);
      index += part.nodes.length;
    }
    final links = _plainStrings(array);
    if (links.isEmpty) {
      return outcome;
    }
    return outcome.merge(
      _readEntries(
        const <Map<String, Object?>>[],
        links,
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: index,
      ),
    );
  }

  /// Reads the servers of one sing-box or Xray configuration, or returns
  /// `null` when it has neither outbounds nor endpoints.
  ///
  /// An Xray configuration names itself in `remarks`, while its server
  /// outbound is tagged `proxy` in every panel's template, so the remarks
  /// are the node's name. Several servers in one configuration keep their
  /// own names after it, so they stay apart.
  ParseOutcome? _readDocument(
    Map<String, Object?> document, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final outbounds = _serversOf(document);
    if (outbounds.isEmpty) {
      return null;
    }
    final outcome = _readEntries(
      outbounds.where(SingBoxOutboundReader.looksLikeServer).toList(),
      const <String>[],
      subscriptionId: subscriptionId,
      groupId: groupId,
      startIndex: startIndex,
    );
    final remarks = MapRead.text(document, <String>['remarks']);
    if (remarks == null || !outcome.hasNodes) {
      return outcome;
    }
    final single = outcome.nodes.length == 1;
    return outcome.copyWith(
      nodes: <ProxyNode>[
        for (final node in outcome.nodes)
          node.copyWith(name: single ? remarks : '$remarks ${node.name}'),
      ],
    );
  }

  /// The outbounds and endpoints of [document], plumbing included.
  ///
  /// Since sing-box 1.11 WireGuard is an endpoint, not an outbound, and a
  /// WARP profile keeps nothing but `direct` among its outbounds.
  static List<Map<String, Object?>> _serversOf(Map<String, Object?> document) =>
      <Map<String, Object?>>[
        ...MapRead.objectList(document, <String>['outbounds', 'outbound']),
        ...MapRead.objectList(document, <String>['endpoints']),
      ];

  /// Whether [object] is a whole configuration rather than one node.
  ///
  /// A sing-box selector has `outbounds` too, but as a list of tags, which
  /// holds no objects.
  static bool _isDocument(Map<String, Object?> object) =>
      _serversOf(object).isNotEmpty;

  ParseOutcome _readEntries(
    List<Map<String, Object?>> objects,
    List<String> links, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final nodes = <ProxyNode>[];
    final failures = <ImportFailure>[];
    var index = startIndex;
    for (final object in objects) {
      try {
        final node = _readObject(object);
        nodes.add(
          node.copyWith(
            subscriptionId: subscriptionId,
            groupId: groupId,
            sortIndex: index,
          ),
        );
        index++;
      } on LinkFormatException catch (error) {
        failures.add(
          ImportFailure(rawLine: _describe(object), reason: error.reason),
        );
      } on Object catch (error) {
        failures.add(
          ImportFailure(
            rawLine: _describe(object),
            reason: 'Could not be read: $error',
          ),
        );
      }
    }
    if (links.isNotEmpty) {
      final parsed = _registry.parseLines(
        links.join('\n'),
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: index,
      );
      nodes.addAll(parsed.nodes);
      failures.addAll(parsed.failures);
    }
    return ParseOutcome(nodes: nodes, failures: failures);
  }

  ProxyNode _readObject(Map<String, Object?> object) {
    // Clash calls the discriminator `type` too, so the tie-breaker is the key
    // that only one of the two formats has.
    final isClash = object.containsKey('name') &&
        !object.containsKey('tag') &&
        !object.containsKey('server_port');
    if (isClash) {
      return ClashProxyReader.read(object);
    }
    return SingBoxOutboundReader.read(object);
  }

  static List<Map<String, Object?>> _asObjects(List<Object?> source) {
    final result = <Map<String, Object?>>[];
    for (final item in source) {
      if (item is Map<String, Object?>) {
        result.add(item);
      } else if (item is Map) {
        result.add(<String, Object?>{
          for (final entry in item.entries) '${entry.key}': entry.value,
        });
      }
    }
    return result;
  }

  static List<String> _plainStrings(List<Object?> source) => <String>[
        for (final item in source)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];

  static String _describe(Map<String, Object?> object) {
    final name = MapRead.text(object, <String>['name', 'tag', 'ps']);
    final type = MapRead.text(object, <String>['type', 'protocol']);
    return name ?? type ?? 'entry';
  }

  bool _hasAnyLink(String body) {
    for (final line in body.split(RegExp(r'[\r\n]+'))) {
      if (_registry.canParse(line.trim())) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeJson(String body) =>
      body.startsWith('{') || body.startsWith('[');

  static String _strip(String body) {
    final withoutBom =
        body.startsWith(byteOrderMark) ? body.substring(1) : body;
    return withoutBom.trim();
  }
}
