/// Method names accepted on the `WireChannels.method` channel.
///
/// Seven, and no more. Adding one means editing the Kotlin side, this list and
/// `docs/wire-protocol.md` in the same pull request.
abstract final class WireMethods {
  /// Brings the tunnel up. Argument: the configuration JSON, as a string.
  static const String start = 'start';

  /// Takes the tunnel down. No argument. Idempotent.
  static const String stop = 'stop';

  /// Restarts the core with a new configuration, keeping the TUN device.
  static const String reload = 'reload';

  /// Points a group at one of its members. Argument: `{group, tag}`.
  static const String select = 'select';

  /// Measures one outbound. Argument: `{tag, url, timeoutMs, group}`.
  static const String urlTest = 'urlTest';

  /// Lists the outbound groups the running core knows about.
  static const String proxies = 'proxies';

  /// Reports the sing-box version string. Not part of the domain port.
  static const String version = 'version';
}
