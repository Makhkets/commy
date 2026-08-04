/// Every JSON field name that crosses the platform boundary.
///
/// Collected in one place so the Kotlin side has a single list to match and so
/// a rename shows up as a single diff. Grouped by the payload the field belongs
/// to; the comments name the channel or the method.
abstract final class WireKeys {
  // ── method arguments and results ──────────────────────────────────────

  /// `select`, `urlTest`: the group tag.
  static const String group = 'group';

  /// `select`, `urlTest`: the outbound tag.
  static const String tag = 'tag';

  /// `urlTest`: the probe URL.
  static const String url = 'url';

  /// `urlTest`: how long the native side waits for the group refresh.
  static const String timeoutMs = 'timeoutMs';

  /// `urlTest` result: measured round trip, or `null` on timeout.
  static const String delayMs = 'delayMs';

  // ── proxies() ─────────────────────────────────────────────────────────

  /// Group type as libbox spells it: `selector`, `urltest`, `fallback`.
  static const String type = 'type';

  /// Tag of the member the group currently points at.
  static const String selected = 'selected';

  /// Members of a group.
  static const String items = 'items';

  /// Last measured delay of a member, in milliseconds. `0` means unmeasured.
  static const String urlTestDelay = 'urlTestDelay';

  // ── /status ───────────────────────────────────────────────────────────

  /// One of the six tunnel states.
  static const String state = 'state';

  /// When the tunnel came up, in epoch milliseconds.
  static const String since = 'since';

  /// Domain node identifier, when the native side happens to know it.
  static const String nodeId = 'nodeId';

  /// Human readable explanation of an `error` state.
  static const String reason = 'reason';

  /// Error code of an `error` state.
  static const String code = 'code';

  // ── /traffic ──────────────────────────────────────────────────────────

  /// Bytes per second going out.
  static const String up = 'up';

  /// Bytes per second coming in.
  static const String down = 'down';

  /// Bytes sent since the tunnel came up.
  static const String upTotal = 'upTotal';

  /// Bytes received since the tunnel came up.
  static const String downTotal = 'downTotal';

  /// Event timestamp, in epoch milliseconds.
  static const String at = 'at';

  // ── /logs ─────────────────────────────────────────────────────────────

  /// Severity name, in the core's own spelling.
  static const String level = 'level';

  /// The log text, raw.
  static const String message = 'message';

  // ── /connections ──────────────────────────────────────────────────────

  /// Connection identifier assigned by the core.
  static const String id = 'id';

  /// Destination host.
  static const String host = 'host';

  /// Routing rule that matched.
  static const String rule = 'rule';

  /// Tag of the outbound the traffic went to.
  static const String outbound = 'outbound';

  /// When the connection opened, in epoch milliseconds.
  static const String start = 'start';

  /// Transport: `tcp` or `udp`.
  static const String network = 'network';

  // ── /intents ──────────────────────────────────────────────────────────
  //
  // Not tunnel state. These name what the Android system handed the app: a
  // tapped link, a shared file, a Quick Settings tap.

  /// Which kind of system input arrived.
  static const String kind = 'kind';

  /// The link or the file location.
  static const String uri = 'uri';

  /// Shared plain text.
  static const String text = 'text';
}
