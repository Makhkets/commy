/// An inclusive pair of integers an XHTTP value is drawn from.
///
/// XHTTP randomises nearly every number it puts on the wire, so its settings
/// are ranges where another transport would have a number. Xray writes one as
/// `"100-1000"`, as `"100"` or as a bare `100`; all three are read here, and a
/// range whose ends are equal is written back as a number.
class XhttpRange {
  /// Creates a range. The ends are stored in order whichever way they came.
  const XhttpRange(int from, int to)
      : from = from <= to ? from : to,
        to = from <= to ? to : from;

  /// The lower end, inclusive.
  final int from;

  /// The upper end, inclusive.
  final int to;

  /// Whether nothing was set: Xray reads `0` as "use the default".
  bool get isZero => from == 0 && to == 0;

  /// Reads whatever a subscription put where a range belongs, or `null`.
  ///
  /// Nothing here throws: a value that makes no sense is a value that was not
  /// given, and the transport's default applies.
  static XhttpRange? tryParse(Object? raw) {
    if (raw is int) {
      return XhttpRange(raw, raw);
    }
    if (raw is double && raw == raw.roundToDouble()) {
      return XhttpRange(raw.toInt(), raw.toInt());
    }
    if (raw is Map) {
      final from = _integer(raw['from'] ?? raw['From']);
      final to = _integer(raw['to'] ?? raw['To']);
      if (from == null && to == null) {
        return null;
      }
      return XhttpRange(from ?? to!, to ?? from!);
    }
    if (raw is! String) {
      return null;
    }
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final single = int.tryParse(text);
    if (single != null) {
      return XhttpRange(single, single);
    }
    // The separator is the first dash that is not a leading minus sign.
    final split = text.indexOf('-', 1);
    if (split < 0) {
      return null;
    }
    final from = int.tryParse(text.substring(0, split).trim());
    final to = int.tryParse(text.substring(split + 1).trim());
    if (from == null || to == null) {
      return null;
    }
    return XhttpRange(from, to);
  }

  /// The value as a configuration writes it: a number, or `"from-to"`.
  Object toWire() => from == to ? from : '$from-$to';

  static int? _integer(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is double && raw == raw.roundToDouble()) {
      return raw.toInt();
    }
    return raw is String ? int.tryParse(raw.trim()) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is XhttpRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => from == to ? '$from' : '$from-$to';
}
