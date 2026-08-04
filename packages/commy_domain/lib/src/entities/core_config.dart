import 'dart:convert';

import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/structural.dart';

/// A complete sing-box configuration, ready to hand to the core.
///
/// Built whole on every start, never patched: the state of the core has to be
/// derivable from the state of the app and nothing else
/// (docs/02-architecture.md, step 5).
///
/// The document holds every credential in the clear, which is why rule R2
/// keeps it out of the plain database and why [toString] never prints it.
class CoreConfig {
  /// Wraps an already-built configuration document.
  const CoreConfig(this.document);

  /// The configuration as a JSON object.
  final JsonMap document;

  /// The configuration as a JSON string, which is what the core consumes.
  String encode() => jsonEncode(document);

  /// Top-level sections present in the document, sorted. Handy in tests.
  List<String> get sections => document.keys.toList()..sort();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoreConfig && Structural.mapEquals(other.document, document);

  @override
  int get hashCode => Structural.mapHash(document);

  /// Never prints the document: it contains every credential in the clear.
  @override
  String toString() => 'CoreConfig(${document.length} sections)';
}
