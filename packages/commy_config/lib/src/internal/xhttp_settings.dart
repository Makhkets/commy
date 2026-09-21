import 'dart:convert';

import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/map_read.dart';
import 'package:commy_config/src/internal/xhttp_range.dart';

/// Everything an XHTTP transport is told besides its host, path and mode.
///
/// A share link carries these as one JSON object in `extra=`; Xray's own
/// configuration spells the same keys inside `xhttpSettings`; Clash.Meta has
/// them in kebab-case under `xhttp-opts`, and the core wants them in
/// snake_case in the `transport` block. It is one set of settings in four
/// spellings, so it is read once, by [XhttpSettings.read] — `MapRead` already
/// compares keys with case and separators removed — and written in the two
/// forms the app produces: [toXray] for links, [toCore] for the core.
///
/// Only what a **client** reads is kept. `noSSEHeader`, `scMaxBufferedPosts`,
/// `scStreamUpServerSecs` and `serverMaxHeaderBytes` configure the server and
/// are dropped: the core decodes with unknown fields disallowed, and a field
/// that does nothing is better left out than refused.
///
/// The rules in [validate] are Xray's, read off `infra/conf/transport_method.go`
/// and mirrored in `core/xhttp/config/options.go`. They are checked here as
/// well because of where the two checks fail: the core refuses the whole
/// document, which leaves the user unable to connect to *any* server because
/// of one bad entry in a subscription; this one refuses the entry.
class XhttpSettings {
  XhttpSettings._({
    required Map<String, Object> values,
    required Map<String, Object> xmux,
    required this.headers,
    required this.hostHeader,
    required Object? downloadSettings,
  })  : _values = values,
        _xmux = xmux,
        _downloadSettings = downloadSettings;

  /// Reads the settings out of [source], whichever spelling it uses.
  ///
  /// Never throws. A value of the wrong shape is a value that was not given.
  factory XhttpSettings.read(Map<String, Object?> source) {
    final values = <String, Object>{};
    for (final field in _fields) {
      final value = _readField(source, field);
      if (value != null) {
        values[field.xray] = value;
      }
    }

    final xmux = <String, Object>{};
    final rawXmux = MapRead.object(source, _xmuxKeys);
    if (rawXmux != null) {
      for (final field in _xmuxFields) {
        final value = _readField(rawXmux, field);
        if (value != null) {
          xmux[field.xray] = value;
        }
      }
    }

    final headers = <String, String>{};
    String? hostHeader;
    final rawHeaders = MapRead.object(source, const <String>['headers']);
    if (rawHeaders != null) {
      for (final entry in rawHeaders.entries) {
        final value = entry.value;
        final text = value is List
            ? (value.isEmpty ? null : '${value.first}')
            : (value == null || value is Map ? null : '$value');
        if (text == null || entry.key.trim().isEmpty) {
          continue;
        }
        // Xray refuses a Host header here outright: the Host of a request has
        // one owner, the `host` setting. A panel that wrote it anyway meant
        // the same thing, so it is kept as that and not as a header.
        if (entry.key.trim().toLowerCase() == 'host') {
          hostHeader = text.trim().isEmpty ? null : text.trim();
          continue;
        }
        headers[entry.key.trim()] = text;
      }
    }

    return XhttpSettings._(
      values: values,
      xmux: xmux,
      headers: headers,
      hostHeader: hostHeader,
      downloadSettings: MapRead.value(
        source,
        const <String>['downloadSettings', 'download'],
      ),
    );
  }

  /// Reads the `extra=` value of a share link, or returns `null` when it is
  /// not a JSON object.
  static XhttpSettings? tryParseExtra(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    return XhttpSettings.read(<String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    });
  }

  /// Modes Xray knows.
  static const Set<String> modes = <String>{
    modeAuto,
    modePacketUp,
    modeStreamUp,
    modeStreamOne,
  };

  /// Let the client decide: stream-one with Reality, packet-up otherwise.
  static const String modeAuto = 'auto';

  /// The upload is cut into short sequenced requests.
  static const String modePacketUp = 'packet-up';

  /// The upload is one streamed request, the download another.
  static const String modeStreamUp = 'stream-up';

  /// One request carries both directions.
  static const String modeStreamOne = 'stream-one';

  /// Longest session id the core accepts; see `MaxSessionIDLength` in Go.
  static const int maxSessionIdLength = 256;

  /// Session ids the server has to be able to tell apart: 2^31.
  static final BigInt _minSessionRoom = BigInt.from(2) << 30;

  static const List<String> _xmuxKeys = <String>[
    'xmux',
    'reuseSettings',
  ];

  static const List<_Field> _fields = <_Field>[
    _Field('xPaddingBytes', 'x_padding_bytes', _Kind.range),
    _Field('noGRPCHeader', 'no_grpc_header', _Kind.flag),
    _Field('scMaxEachPostBytes', 'sc_max_each_post_bytes', _Kind.range),
    _Field('scMinPostsIntervalMs', 'sc_min_posts_interval_ms', _Kind.range),
    _Field('xPaddingObfsMode', 'x_padding_obfs_mode', _Kind.flag),
    _Field('xPaddingKey', 'x_padding_key', _Kind.text),
    _Field('xPaddingHeader', 'x_padding_header', _Kind.text),
    _Field('xPaddingPlacement', 'x_padding_placement', _Kind.text),
    _Field('xPaddingMethod', 'x_padding_method', _Kind.text),
    _Field('uplinkHTTPMethod', 'uplink_http_method', _Kind.text),
    // Xray renamed these two after v26.3.27; servers of both kinds exist.
    _Field(
      'sessionPlacement',
      'session_placement',
      _Kind.text,
      aliases: <String>['sessionIDPlacement'],
    ),
    _Field(
      'sessionKey',
      'session_key',
      _Kind.text,
      aliases: <String>['sessionIDKey'],
    ),
    _Field('seqPlacement', 'seq_placement', _Kind.text),
    _Field('seqKey', 'seq_key', _Kind.text),
    _Field('uplinkDataPlacement', 'uplink_data_placement', _Kind.text),
    _Field('uplinkDataKey', 'uplink_data_key', _Kind.text),
    _Field('uplinkChunkSize', 'uplink_chunk_size', _Kind.range),
    _Field('sessionIDTable', 'session_id_table', _Kind.text),
    _Field('sessionIDLength', 'session_id_length', _Kind.range),
  ];

  static const List<_Field> _xmuxFields = <_Field>[
    _Field('maxConcurrency', 'max_concurrency', _Kind.range),
    _Field('maxConnections', 'max_connections', _Kind.range),
    _Field('cMaxReuseTimes', 'c_max_reuse_times', _Kind.range),
    _Field('hMaxRequestTimes', 'h_max_request_times', _Kind.range),
    _Field('hMaxReusableSecs', 'h_max_reusable_secs', _Kind.range),
    _Field('hKeepAlivePeriod', 'h_keep_alive_period', _Kind.integer),
  ];

  static const Map<String, String> _predefinedTables = <String, String>{
    'ALPHABET': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'Alphabet': 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
    'BASE36': '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'Base62': '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
    'HEX': '0123456789ABCDEF',
    'alphabet': 'abcdefghijklmnopqrstuvwxyz',
    'base36': '0123456789abcdefghijklmnopqrstuvwxyz',
    'hex': '0123456789abcdef',
    'number': '0123456789',
  };

  final Map<String, Object> _values;
  final Map<String, Object> _xmux;
  final Object? _downloadSettings;

  /// Extra request headers, without `Host`.
  final Map<String, String> headers;

  /// The `Host` a source put among the headers, where Xray does not allow it.
  ///
  /// The caller uses it as the transport's host when no host was given.
  final String? hostHeader;

  /// Whether the source asked for a second route for the download.
  ///
  /// The core does not implement it (docs/adr/0010-xhttp-transport.md): both
  /// directions then use the main route, which is the same server in every
  /// deployment this was written for. The value is kept in [toXray] so that a
  /// node exported again is the node that was imported.
  bool get hasDownloadSettings => _downloadSettings != null;

  /// Whether the source set nothing a client reads.
  bool get isEmpty =>
      _values.isEmpty &&
      _xmux.isEmpty &&
      headers.isEmpty &&
      _downloadSettings == null;

  /// The settings as Xray spells them: the `extra` of a share link.
  Map<String, Object?> toXray() {
    final document = <String, Object?>{};
    if (headers.isNotEmpty) {
      document['headers'] = headers;
    }
    for (final field in _fields) {
      final value = _values[field.xray];
      if (value == null) {
        continue;
      }
      document[field.xray] = _wire(value);
      // Written under both names, because the reader may be an Xray from
      // either side of the rename and Xray ignores keys it does not know.
      for (final alias in field.aliases) {
        document[alias] = _wire(value);
      }
    }
    if (_xmux.isNotEmpty) {
      document['xmux'] = <String, Object?>{
        for (final field in _xmuxFields)
          if (_xmux[field.xray] != null) field.xray: _wire(_xmux[field.xray]!),
      };
    }
    if (_downloadSettings != null) {
      document['downloadSettings'] = _downloadSettings;
    }
    return document;
  }

  /// [toXray] as the text a link carries, or `null` when there is nothing.
  String? toExtraJson() => isEmpty ? null : jsonEncode(toXray());

  /// The settings as the core's `transport` block spells them.
  Map<String, Object?> toCore() {
    final block = <String, Object?>{};
    if (headers.isNotEmpty) {
      block['headers'] = headers;
    }
    for (final field in _fields) {
      final value = _values[field.xray];
      if (value != null) {
        block[field.core] = _wire(value);
      }
    }
    if (_xmux.isNotEmpty) {
      block['xmux'] = <String, Object?>{
        for (final field in _xmuxFields)
          if (_xmux[field.xray] != null) field.core: _wire(_xmux[field.xray]!),
      };
    }
    return block;
  }

  /// Checks the rules Xray checks, for a transport running in [mode].
  ///
  /// Throws [ConfigBuildException] naming the first rule that is broken.
  void validate(String mode) {
    if (!modes.contains(mode)) {
      throw ConfigBuildException('XHTTP mode "$mode" does not exist');
    }

    final padding = _range('xPaddingBytes');
    if (padding != null &&
        !padding.isZero &&
        (padding.from <= 0 || padding.to <= 0)) {
      throw const ConfigBuildException(
        'XHTTP padding cannot be switched off: xPaddingBytes must be positive',
      );
    }
    _oneOf(
      'xPaddingPlacement',
      const <String>{'cookie', 'header', 'query', 'queryInHeader'},
    );
    _oneOf('xPaddingMethod', const <String>{'repeat-x', 'tokenish'});

    final dataPlacement = _text('uplinkDataPlacement');
    _oneOf(
      'uplinkDataPlacement',
      const <String>{'auto', 'body', 'cookie', 'header'},
    );
    if ((dataPlacement == 'cookie' || dataPlacement == 'header') &&
        mode != modePacketUp) {
      throw ConfigBuildException(
        'XHTTP uplinkDataPlacement "$dataPlacement" needs mode packet-up',
      );
    }
    if (_text('uplinkHTTPMethod')?.toUpperCase() == 'GET' &&
        mode != modePacketUp) {
      throw const ConfigBuildException(
        'XHTTP uplinkHTTPMethod GET needs mode packet-up',
      );
    }
    const placements = <String>{'path', 'cookie', 'header', 'query'};
    _oneOf('sessionPlacement', placements);
    _oneOf('seqPlacement', placements);

    final table = _text('sessionIDTable');
    if (table != null) {
      final alphabet = _predefinedTables[table] ?? table;
      final length = _range('sessionIDLength');
      if (length == null || length.from <= 0) {
        throw const ConfigBuildException(
          'XHTTP sessionIDTable needs a positive sessionIDLength',
        );
      }
      if (length.to > maxSessionIdLength) {
        throw const ConfigBuildException(
          'XHTTP sessionIDLength is longer than any server would accept',
        );
      }
      if (alphabet.codeUnits.any((unit) => unit >= 0x80)) {
        throw const ConfigBuildException(
          'XHTTP sessionIDTable must contain only ASCII characters',
        );
      }
      var room = BigInt.zero;
      final base = BigInt.from(alphabet.length);
      for (var size = length.from; size <= length.to; size++) {
        room += base.pow(size);
      }
      if (room < _minSessionRoom) {
        throw const ConfigBuildException(
          'XHTTP sessionIDTable and sessionIDLength leave too few session ids',
        );
      }
    }

    final postBytes = _range('scMaxEachPostBytes');
    if (postBytes != null && !postBytes.isZero && postBytes.from <= 0) {
      throw const ConfigBuildException(
        'XHTTP scMaxEachPostBytes must be positive',
      );
    }
    final postInterval = _range('scMinPostsIntervalMs');
    if (postInterval != null && postInterval.from < 0) {
      throw const ConfigBuildException(
        'XHTTP scMinPostsIntervalMs cannot be negative',
      );
    }

    final connections = _xmux['maxConnections'];
    final concurrency = _xmux['maxConcurrency'];
    if (connections is XhttpRange &&
        concurrency is XhttpRange &&
        connections.to > 0 &&
        concurrency.to > 0) {
      throw const ConfigBuildException(
        'XHTTP xmux cannot set both maxConnections and maxConcurrency',
      );
    }
  }

  XhttpRange? _range(String key) {
    final value = _values[key];
    return value is XhttpRange ? value : null;
  }

  String? _text(String key) {
    final value = _values[key];
    return value is String ? value : null;
  }

  void _oneOf(String key, Set<String> allowed) {
    final value = _text(key);
    if (value != null && !allowed.contains(value)) {
      throw ConfigBuildException('XHTTP $key "$value" does not exist');
    }
  }

  static Object _wire(Object value) =>
      value is XhttpRange ? value.toWire() : value;

  static Object? _readField(Map<String, Object?> source, _Field field) {
    final keys = <String>[field.xray, ...field.aliases];
    switch (field.kind) {
      case _Kind.range:
        final range = XhttpRange.tryParse(MapRead.value(source, keys));
        return range == null || range.isZero ? null : range;
      case _Kind.flag:
        // `false` is every flag's default; only `true` is worth carrying.
        return (MapRead.boolean(source, keys) ?? false) ? true : null;
      case _Kind.text:
        return MapRead.text(source, keys);
      case _Kind.integer:
        final number = MapRead.integer(source, keys);
        return number == null || number == 0 ? null : number;
    }
  }
}

enum _Kind { range, flag, text, integer }

class _Field {
  const _Field(
    this.xray,
    this.core,
    this.kind, {
    this.aliases = const <String>[],
  });

  /// The key in an Xray document and in the `extra` of a share link.
  final String xray;

  /// The key in the core's `transport` block.
  final String core;

  final _Kind kind;

  /// Other names Xray has used for the same key.
  final List<String> aliases;
}
