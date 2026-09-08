/// What the external IP endpoint answered: the address the tunnel exits
/// from, and the country when the service names one.
///
/// Never stored. Exception E-1 of docs/09-security-privacy.md allows the
/// request and forbids keeping the answer; this object lives for the length
/// of one toast.
class IpCheckResult {
  /// Creates a result.
  const IpCheckResult({required this.ip, this.country});

  /// The address as the endpoint reported it, IPv4 or IPv6.
  final String ip;

  /// A country code or name, if the endpoint gave one.
  final String? country;

  /// `203.0.113.7 · NL`, or just the address.
  String get label {
    final where = country;
    if (where == null || where.isEmpty) {
      return ip;
    }
    return '$ip · $where';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IpCheckResult && other.ip == ip && other.country == country;

  @override
  int get hashCode => Object.hash(ip, country);

  @override
  String toString() => 'IpCheckResult($label)';
}
