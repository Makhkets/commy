/// Method names accepted on the `WireChannels.method` channel.
///
/// Seven for the tunnel, and no more: the tunnel protocol is closed. Adding
/// one means editing the Kotlin side, this list and `docs/wire-protocol.md` in
/// the same pull request.
///
/// [openVpnSettings] and [setStartOnBoot] are not tunnel commands, and they
/// are counted separately for that reason — see their own notes below.
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

  /// Turns the boot receiver on or off. Argument: a bare `bool`. No result.
  ///
  /// Not a tunnel command either. "Connect on boot" is a stored setting on
  /// the Dart side and a manifest component on the Kotlin side, and the two
  /// have to agree: a receiver enabled while the switch is off runs at every
  /// boot for nothing, and one disabled while the switch is on is a promise
  /// the settings screen makes and nobody keeps.
  static const String setStartOnBoot = 'setStartOnBoot';
}
