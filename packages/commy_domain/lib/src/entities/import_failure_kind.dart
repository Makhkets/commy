/// Why an entry could not be imported, as a fact the app words for the user.
///
/// The parsers used to say it in English only, and the import panel showed
/// that sentence as it came — under a Russian heading, in a Russian UI, and
/// for an unexpected throw a Dart exception's own text. The words belong to
/// the app's translations (CLAUDE.md §5), as they do for a routing warning;
/// `ImportFailure.reason` keeps the English for the log.
enum ImportFailureKind {
  /// The entry could not be read: a broken link, a value that makes no sense,
  /// anything the other kinds do not name.
  malformed,

  /// The line is not a link to a server at all.
  notALink,

  /// A link of a scheme no parser knows. The subject is the scheme, with its
  /// `://`.
  unsupportedScheme,

  /// A server that needs something the core cannot do — a transport, an
  /// encryption, a proxy type. The subject names it, when it can be named.
  unsupported,

  /// A link without something every server needs: an address, a port, a
  /// user id, a password, a key.
  incomplete,

  /// The subscription answered with nothing.
  emptyBody,

  /// The body is none of the formats the reader knows.
  unknownFormat,
}
