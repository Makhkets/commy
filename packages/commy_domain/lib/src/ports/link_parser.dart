import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';

/// Turns arbitrary user input into nodes.
///
/// Accepts protocol links, a list of them, the same list in base64, a Clash
/// YAML document and a sing-box or Xray JSON document. Lenient about what it
/// takes in, strict about what it puts out: nothing half-understood becomes a
/// node, and nothing from the internet reaches the core unvalidated.
abstract interface class LinkParser {
  /// Parses [input], returning both the nodes and the entries that failed.
  ///
  /// Returns `Err` only when the input as a whole made no sense. A document
  /// where some entries were broken is a success with failures attached.
  Result<ParseOutcome, CommyFailure> parse(String input);

  /// Cheap check used to light up the "paste" button when the clipboard has
  /// something we can read.
  bool canParse(String input);

  /// Renders [node] back into a protocol link, for sharing and for QR codes.
  ///
  /// Returns `Err` for protocols that have no agreed link format.
  Result<String, CommyFailure> toLink(ProxyNode node);
}
