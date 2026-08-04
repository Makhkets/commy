// `Uri.decodeComponent` reports malformed escapes with ArgumentError — verified
// against '%zz', '%', 'a%2' and a truncated multi-byte sequence, all of which
// throw ArgumentError and never an Exception. So there is no exception to catch
// instead, and the only alternative is to reimplement the decoder in order to
// validate first. The lint is right in general and wrong here; the suppression
// is file-wide because this file exists solely to wrap that one call.
// ignore_for_file: avoid_catching_errors

/// Percent-encoding helpers that never throw.
///
/// Links pasted by users are routinely half-encoded: a password containing
/// `%` that nobody escaped, a fragment with a stray `%zz`.
/// `Uri.decodeComponent` throws on those, and an import must not die because
/// one node was sloppy.
abstract final class Percent {
  /// Decodes [source], returning it unchanged when it is not valid encoding.
  static String decode(String source) {
    if (!source.contains('%')) {
      return source;
    }
    try {
      return Uri.decodeComponent(source);
    } on ArgumentError {
      return source;
    } on FormatException {
      return source;
    }
  }

  /// Encodes [source] for use inside a URI component.
  static String encode(String source) => Uri.encodeComponent(source);

  /// Encodes [source] for use as a URI fragment.
  ///
  /// Keeps the characters a node name is allowed to hold verbatim, so that a
  /// shared link stays readable instead of turning into a wall of `%D0%9C`.
  static String encodeFragment(String source) =>
      Uri.encodeFull(source).replaceAll('#', '%23');

  /// Encodes [source] for use as a query value.
  ///
  /// Escapes only what would break the link apart again. `alpn=h2,http/1.1`
  /// stays readable, which matters because these links are read by humans and
  /// pasted into other clients.
  static String encodeQueryValue(String source) {
    final buffer = StringBuffer();
    for (final rune in source.runes) {
      final char = String.fromCharCode(rune);
      if (_querySafe.hasMatch(char)) {
        buffer.write(char);
      } else {
        buffer.write(Uri.encodeComponent(char));
      }
    }
    return buffer.toString();
  }

  static final RegExp _querySafe = RegExp(r'^[A-Za-z0-9\-._~:/,*]$');
}
