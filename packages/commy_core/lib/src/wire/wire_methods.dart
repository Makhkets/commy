/// Method names accepted on the `WireChannels.method` channel.
///
/// Seven for the tunnel, and no more: the tunnel protocol is closed. Adding
/// one means editing the Kotlin side, this list and `docs/wire-protocol.md` in
/// the same pull request.
///
/// [openVpnSettings] is the one method that is not a tunnel command, and it is
/// counted separately for that reason — see its own note below.
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

  /// Opens the system VPN settings screen. No argument, no result.
  ///
  /// Not a tunnel command. It exists because the only kill switch on Android
  /// that actually holds is the system one — "Always-on VPN" together with
  /// "Block connections without VPN" — and an app cannot promise that itself:
  /// once the process is killed there is nothing left to block with. So the
  /// app names the guarantee, says who provides it, and offers to open it.
  static const String openVpnSettings = 'openVpnSettings';
}
