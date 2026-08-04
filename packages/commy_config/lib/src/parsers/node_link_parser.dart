import 'package:commy_domain/commy_domain.dart';

/// One protocol's share-link format, read and written.
///
/// Implementations are lenient about what they accept and strict about what
/// they produce (docs/02-architecture.md, step 2): anything half-understood
/// raises `LinkFormatException` instead of becoming a node with holes in it.
abstract interface class NodeLinkParser {
  /// Schemes this parser answers for, lower-case and without `://`.
  Set<String> get schemes;

  /// The protocol the produced nodes carry.
  Protocol get protocol;

  /// Turns one link into a node.
  ///
  /// Throws `LinkFormatException` with a reason written for a human when the
  /// link cannot be understood.
  ProxyNode parse(String raw);

  /// Renders [node] back into a link of this protocol.
  ///
  /// Throws `LinkFormatException` when the node is missing something the link
  /// format cannot express without.
  String toLink(ProxyNode node);
}
