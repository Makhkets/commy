import 'package:commy_domain/commy_domain.dart';

/// The operating system the generated configuration is going to run on.
///
/// The core is the same everywhere; what differs is which knobs exist. Android
/// is the only platform with package-level rules, Apple's network extension is
/// the only one that must stay on the userspace stack (rule R7), and the Clash
/// API is a desktop-only affair (docs/06-data-model.md).
enum ConfigPlatform {
  /// Android, through `VpnService`.
  android(
    supportsPackageRules: true,
    supportsProcessRules: false,
    forcesGvisorStack: false,
    allowsClashApi: false,
  ),

  /// iOS, inside `NEPacketTunnelProvider`.
  ios(
    supportsPackageRules: false,
    supportsProcessRules: false,
    forcesGvisorStack: true,
    allowsClashApi: false,
  ),

  /// macOS, inside `NEPacketTunnelProvider` or the privileged helper.
  macos(
    supportsPackageRules: false,
    supportsProcessRules: true,
    forcesGvisorStack: false,
    allowsClashApi: true,
  ),

  /// Windows, through the elevated service and Wintun.
  windows(
    supportsPackageRules: false,
    supportsProcessRules: true,
    forcesGvisorStack: false,
    allowsClashApi: true,
  ),

  /// Linux, through the polkit helper.
  linux(
    supportsPackageRules: false,
    supportsProcessRules: true,
    forcesGvisorStack: false,
    allowsClashApi: true,
  );

  const ConfigPlatform({
    required this.supportsPackageRules,
    required this.supportsProcessRules,
    required this.forcesGvisorStack,
    required this.allowsClashApi,
  });

  /// Whether `include_package` and `exclude_package` mean anything here.
  final bool supportsPackageRules;

  /// Whether route rules may match on process name or path.
  final bool supportsProcessRules;

  /// Whether the TUN stack is pinned to gVisor regardless of the setting.
  ///
  /// True on iOS: the system stack is unavailable inside the extension, and
  /// rule R7 leaves no room to find out the hard way.
  final bool forcesGvisorStack;

  /// Whether the Clash API may be exposed at all.
  ///
  /// Mobile gets its data through libbox, so an extra HTTP server there is
  /// weight without a purpose.
  final bool allowsClashApi;

  /// Whether this is one of the desktop platforms.
  bool get isDesktop => supportsProcessRules;

  /// The stack this platform will actually use given [requested].
  TunStack resolveStack(TunStack requested) =>
      forcesGvisorStack ? TunStack.gvisor : requested;
}
