/// A server the builder could not express, and built the document without.
///
/// The app hands the builder every server it has stored, so that switching
/// does not mean reconnecting. One of them being malformed — Reality with no
/// public key, a port of 70000, an XHTTP setting Xray itself would refuse — is
/// no reason for the others not to connect, so it is left out and reported
/// here. It is a fact about a server, which is why it does not travel with the
/// routing warnings: those are shown on the routing screen, under a heading
/// about rules.
class LeftOutNode {
  /// Creates the record.
  const LeftOutNode({
    required this.nodeId,
    required this.name,
    required this.reason,
  });

  /// Identifier of the server.
  final String nodeId;

  /// Its display name, for a message a person reads.
  final String name;

  /// Why it could not be built, as a sentence. Holds no credentials.
  final String reason;

  @override
  String toString() => '"$name" was left out: $reason';
}
