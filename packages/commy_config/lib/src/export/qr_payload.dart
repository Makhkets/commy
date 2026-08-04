import 'package:commy_config/src/export/export_outcome.dart';
import 'package:commy_config/src/export/node_link_exporter.dart';
import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the strings that go into a QR code.
///
/// A QR code is only a transport for text, so this is deliberately thin. What
/// it does add is the size guard: past roughly two thousand characters a code
/// stops being scannable by a phone across a table, and silently producing an
/// unreadable image is worse than saying so.
class QrPayload {
  /// Creates a builder over [exporter].
  QrPayload({NodeLinkExporter? exporter})
      : _exporter = exporter ?? NodeLinkExporter();

  /// Longest payload worth encoding.
  ///
  /// Version 40 at error correction level L holds 2 953 bytes; this leaves
  /// room for the encoder and keeps the module count scannable.
  static const int maxLength = 2000;

  final NodeLinkExporter _exporter;

  /// The payload for a single node: its share link.
  Result<String, CommyFailure> forNode(ProxyNode node) {
    final result = _exporter.toLink(node);
    final link = result.valueOrNull;
    if (link == null) {
      return result;
    }
    return _guard(link);
  }

  /// The payload for a list of nodes: the links, base64 wrapped.
  ///
  /// Base64 is what every other client expects a multi-node QR to hold, so it
  /// is what we emit even though the plain list would scan just as well.
  Result<String, CommyFailure> forNodes(Iterable<ProxyNode> nodes) {
    final outcome = _exporter.toLinks(nodes);
    if (!outcome.hasLinks) {
      return const Err<String, CommyFailure>(
        ConfigInvalidFailure('None of these nodes has a share link format'),
      );
    }
    return _guard(LenientBase64.encode(outcome.document));
  }

  /// The payload for a subscription: the URL itself.
  ///
  /// Sharing a subscription URL shares an access token with it. The caller is
  /// expected to have asked the user first; this method only formats.
  Result<String, CommyFailure> forSubscription(Subscription subscription) =>
      _guard(subscription.url.toString());

  /// Renders [nodes] and reports what could not be rendered.
  ExportOutcome describe(Iterable<ProxyNode> nodes) => _exporter.toLinks(nodes);

  Result<String, CommyFailure> _guard(String payload) {
    if (payload.length > maxLength) {
      return Err<String, CommyFailure>(
        ConfigInvalidFailure(
          'Payload is ${payload.length} characters, which will not scan '
          'reliably; the limit is $maxLength',
        ),
      );
    }
    return Ok<String, CommyFailure>(payload);
  }
}
