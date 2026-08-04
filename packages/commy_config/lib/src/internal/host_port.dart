/// A server address split into host and port.
///
/// Written by hand rather than delegated to `Uri`, because the input is not
/// guaranteed to be a valid URI: ports arrive with whitespace around them,
/// IPv6 literals arrive both with and without brackets, and hosts arrive
/// upper-cased.
class HostPort {
  /// Creates an address.
  const HostPort({required this.host, this.port});

  /// Parses `host`, `host:port`, `[v6]:port` or a bare IPv6 literal.
  ///
  /// Returns `null` when nothing usable is left after trimming.
  static HostPort? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('[')) {
      return _parseBracketed(trimmed);
    }
    final colon = trimmed.lastIndexOf(':');
    if (colon < 0) {
      return _hostOnly(trimmed);
    }
    final head = trimmed.substring(0, colon);
    if (head.contains(':')) {
      // More than one colon and no brackets: an IPv6 literal without a port.
      return _hostOnly(trimmed);
    }
    final port = parsePort(trimmed.substring(colon + 1));
    if (port == null) {
      return null;
    }
    final host = head.trim();
    return host.isEmpty ? null : HostPort(host: _normalise(host), port: port);
  }

  /// Parses a port, returning `null` unless it is a number in `1..65535`.
  static int? parsePort(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 5) {
      return null;
    }
    for (final unit in trimmed.codeUnits) {
      if (unit < 0x30 || unit > 0x39) {
        return null;
      }
    }
    final value = int.tryParse(trimmed);
    if (value == null || value < 1 || value > 65535) {
      return null;
    }
    return value;
  }

  /// Whether [host] is shaped like something we can hand to the core.
  ///
  /// Deliberately loose: hostnames, IPv4 and IPv6 literals all pass, anything
  /// with whitespace or a slash in it does not.
  static bool isPlausibleHost(String host) {
    if (host.isEmpty || host.length > 253) {
      return false;
    }
    for (final unit in host.codeUnits) {
      final isForbidden = unit <= 0x20 ||
          unit == 0x2F || // /
          unit == 0x3F || // ?
          unit == 0x23 || // #
          unit == 0x40 || // @
          unit == 0x5B || // [
          unit == 0x5D; // ]
      if (isForbidden) {
        return false;
      }
    }
    return true;
  }

  /// Hostname or address, never bracketed.
  final String host;

  /// Port, or `null` when the input did not carry one.
  final int? port;

  /// Whether [host] is an IPv6 literal.
  bool get isIpv6 => host.contains(':');

  /// The host as it must appear inside a URI: bracketed when IPv6.
  String get literal => isIpv6 ? '[$host]' : host;

  /// The address as `host:port`, bracketing IPv6, omitting a missing port.
  String get authority => port == null ? literal : '$literal:$port';

  static HostPort? _parseBracketed(String trimmed) {
    final close = trimmed.indexOf(']');
    if (close < 0) {
      return null;
    }
    final host = trimmed.substring(1, close).trim();
    if (host.isEmpty) {
      return null;
    }
    final rest = trimmed.substring(close + 1).trim();
    if (rest.isEmpty) {
      return HostPort(host: _normalise(host));
    }
    if (!rest.startsWith(':')) {
      return null;
    }
    final port = parsePort(rest.substring(1));
    return port == null ? null : HostPort(host: _normalise(host), port: port);
  }

  static HostPort? _hostOnly(String trimmed) {
    final host = trimmed.trim();
    return host.isEmpty ? null : HostPort(host: _normalise(host));
  }

  static String _normalise(String host) => host.toLowerCase();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostPort && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'HostPort($authority)';
}
