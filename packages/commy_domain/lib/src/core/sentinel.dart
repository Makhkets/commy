/// Marker meaning "this argument was not supplied".
///
/// Hand-written `copyWith` methods take nullable fields as `Object?` defaulted
/// to [Sentinel.unset]. Comparing with [identical] tells "keep what you have"
/// apart from "set this to null", which a plain `?? this.field` cannot do.
abstract final class Sentinel {
  /// The marker instance. Compare with [identical], never with `==`.
  static const Object unset = _Unset();
}

class _Unset {
  const _Unset();

  @override
  String toString() => '<unset>';
}
