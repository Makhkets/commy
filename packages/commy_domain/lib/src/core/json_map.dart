/// A decoded JSON object.
///
/// Every hand-written `toJson` returns one of these and every `fromJson`
/// accepts one. Codegen is deliberately absent from this package — see
/// docs/adr/0006-codegen-and-native-layout.md.
typedef JsonMap = Map<String, Object?>;
