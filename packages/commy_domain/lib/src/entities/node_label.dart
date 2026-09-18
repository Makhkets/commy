import 'package:commy_domain/src/entities/proxy_node.dart';

/// A server's name as the screen shows it: the words, and the country apart.
///
/// Panels do not send a country. They type one into the name as a flag emoji —
/// `🇨🇿 Prague 01` — and that is the only place it exists: no link format and
/// no subscription header carries a country field. Read literally, the list
/// then draws a neutral chip in the flag slot and an emoji flag next to it,
/// which is the country shown zero times where it belongs and once where
/// emoji flags are banned (see `CountryFlag` in `commy_ui` for why).
///
/// So the flag is read out of the name. A flag emoji is two *regional
/// indicator* code points, U+1F1E6 to U+1F1FF, one per letter of an ISO 3166-1
/// alpha-2 code — `🇨🇿` is literally `C` `Z`. That makes this a lookup rather
/// than a guess: nothing here matches on words like "Germany" or on stray
/// two-letter tokens, because `IN`, `IT`, `NO`, `AT` and `IS` are words first
/// and countries second.
///
/// The stored name is never rewritten. It is what the panel wrote, it is what
/// an exported link carries back out, and a subscription refresh compares
/// against it. Only the label on screen drops the flag.
final class NodeLabel {
  /// Creates a label from already separated parts.
  const NodeLabel({required this.text, this.countryCode});

  /// Reads [name] as a panel wrote it.
  ///
  /// [countryCode] is a code known from elsewhere — `ProxyNode.countryCode` —
  /// and wins over whatever the name says: it was derived on purpose, the
  /// emoji is decoration somebody typed.
  ///
  /// The flag is taken out of the text only when the name holds exactly one.
  /// A relay named `🇩🇪→🇳🇱` is describing a route, and cutting the first
  /// flag off it would leave an arrow pointing out of nowhere; such a name is
  /// shown whole, and the slot still gets the first country.
  factory NodeLabel.parse(String name, {String? countryCode}) {
    final runes = name.runes.toList(growable: false);
    int? flagAt;
    var flags = 0;
    for (var index = 0; index + 1 < runes.length; index++) {
      if (_isIndicator(runes[index]) && _isIndicator(runes[index + 1])) {
        flagAt ??= index;
        flags++;
        // Indicators pair up left to right: four in a row are two flags, not
        // three overlapping ones.
        index++;
      }
    }

    final known = _normalized(countryCode);
    if (flagAt == null) {
      return NodeLabel(text: name, countryCode: known);
    }
    final fromName = String.fromCharCodes(<int>[
      runes[flagAt] - _indicatorA + _letterA,
      runes[flagAt + 1] - _indicatorA + _letterA,
    ]);
    if (flags > 1) {
      return NodeLabel(text: name, countryCode: known ?? fromName);
    }

    final rest = <int>[
      ...runes.take(flagAt),
      ...runes.skip(flagAt + 2),
    ];
    final text = _tidy(String.fromCharCodes(rest));
    return NodeLabel(
      // A name that was nothing but a flag keeps it: an empty row is worse
      // than an emoji, and there is nothing else to call the server.
      text: text.isEmpty ? name : text,
      countryCode: known ?? fromName,
    );
  }

  /// The label of [node].
  factory NodeLabel.of(ProxyNode node) =>
      NodeLabel.parse(node.name, countryCode: node.countryCode);

  /// The name without the flag a panel typed into it.
  final String text;

  /// ISO 3166-1 alpha-2 code in upper case, or `null` when nothing names one.
  ///
  /// `EU` is not an ISO country and is passed through all the same: panels
  /// use 🇪🇺 for their auto-select entry, and `CountryFlag` draws it.
  final String? countryCode;

  static const int _indicatorA = 0x1F1E6;
  static const int _indicatorZ = 0x1F1FF;
  static const int _letterA = 0x41;

  static bool _isIndicator(int rune) =>
      rune >= _indicatorA && rune <= _indicatorZ;

  static String? _normalized(String? code) {
    final trimmed = code?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed.toUpperCase();
  }

  /// Closes the gap a removed flag leaves behind.
  ///
  /// Panels separate the flag from the words with a space, a dash, a bar or a
  /// middle dot — `🇳🇱 | Amsterdam`, `Amsterdam - 🇳🇱` — and a label that
  /// opens or ends with that separator reads as a typo.
  static String _tidy(String text) {
    var result = text.trim();
    while (result.isNotEmpty && _separators.contains(result[0])) {
      result = result.substring(1).trimLeft();
    }
    while (
        result.isNotEmpty && _separators.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1).trimRight();
    }
    return result.replaceAll(_runsOfSpace, ' ');
  }

  static const String _separators = '|-–—·•:,/';

  static final RegExp _runsOfSpace = RegExp(r'\s{2,}');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeLabel &&
          other.text == text &&
          other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(text, countryCode);

  @override
  String toString() => 'NodeLabel($countryCode, $text)';
}
