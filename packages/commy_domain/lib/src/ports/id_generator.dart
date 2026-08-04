/// Source of identifiers for newly created entities.
///
/// A port rather than a call to a uuid package, because commy_domain has no
/// dependencies and because tests need identifiers that do not change between
/// runs — golden output has to be reproducible.
abstract interface class IdGenerator {
  /// Returns a fresh identifier, unique within this installation.
  String newId();
}
