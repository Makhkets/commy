import 'dart:convert';

/// Base64 handling that survives what real panels actually emit.
///
/// Subscriptions arrive base64-wrapped more often than not, and every panel
/// wraps them slightly differently: standard or URL-safe alphabet, padding
/// present or stripped, a newline every 76 characters or none at all. Being
/// strict here means refusing perfectly good subscriptions, so we are not.
abstract final class LenientBase64 {
  /// Shortest string worth trying to decode.
  ///
  /// Below this every second word decodes into three bytes of noise.
  static const int minimumLength = 8;

  /// Share of control characters above which a decode is called a mistake.
  static const double printableThreshold = 0.05;

  static final RegExp _whitespace = RegExp(r'\s');

  static final RegExp _alphabet = RegExp(r'^[A-Za-z0-9+/\-_=]+$');

  /// Decodes [source] into bytes, or returns `null` when it is not base64.
  ///
  /// Accepts both alphabets, tolerates missing padding and ignores every
  /// whitespace character anywhere in the input.
  static List<int>? decodeToBytes(String source) {
    final compact = source.replaceAll(_whitespace, '');
    if (compact.length < minimumLength || !_alphabet.hasMatch(compact)) {
      return null;
    }
    final normalised =
        compact.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
    final remainder = normalised.length % 4;
    if (remainder == 1) {
      return null;
    }
    final padded = remainder == 0
        ? normalised
        : normalised.padRight(normalised.length + 4 - remainder, '=');
    try {
      return base64.decode(padded);
    } on FormatException {
      return null;
    }
  }

  /// Decodes [source] into text, or returns `null` when that makes no sense.
  ///
  /// Returns `null` when the bytes are not valid UTF-8 or when the result is
  /// mostly control characters, which is what happens when a plain link list
  /// happens to consist of base64-legal characters.
  static String? decodeToString(String source) {
    final bytes = decodeToBytes(source);
    if (bytes == null) {
      return null;
    }
    try {
      final text = utf8.decode(bytes);
      return isMostlyPrintable(text) ? text : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether [text] reads like text rather than like decoded noise.
  static bool isMostlyPrintable(String text) {
    if (text.isEmpty) {
      return false;
    }
    var control = 0;
    for (final unit in text.codeUnits) {
      final isAllowedWhitespace = unit == 0x09 || unit == 0x0A || unit == 0x0D;
      if (unit < 0x20 && !isAllowedWhitespace) {
        control++;
      }
    }
    return control / text.length <= printableThreshold;
  }

  /// Encodes [source] as standard base64 with padding.
  static String encode(String source) => base64.encode(utf8.encode(source));

  /// Encodes [source] as URL-safe base64 without padding.
  static String encodeUrlSafe(String source) {
    return base64Url.encode(utf8.encode(source)).replaceAll('=', '');
  }
}
