import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/entities/log_line.dart';

/// Theme preference. Deliberately not Flutter's `ThemeMode`: rule R5.
enum AppThemeMode {
  /// Follow the operating system.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// Which TUN stack the core uses.
enum TunStack {
  /// The operating system stack. Fastest, not available everywhere.
  system(wireName: 'system'),

  /// The userspace gVisor stack. Mandatory on iOS — see rule R7.
  gvisor(wireName: 'gvisor'),

  /// gVisor for TCP, system for UDP.
  mixed(wireName: 'mixed');

  const TunStack({required this.wireName});

  /// Value the sing-box core expects.
  final String wireName;
}

/// Everything the user can toggle that is not routing or DNS.
class AppSettings {
  /// Creates the settings.
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.locale,
    this.killSwitch = false,
    this.autoConnect = false,
    this.startOnBoot = false,
    this.hideUnavailable = false,
    this.latencyProbeUrl = defaultLatencyProbeUrl,
    this.ipCheckUrl = '',
    this.logLevel = LogLevel.info,
    this.allowLan = false,
    this.mixedPort = defaultMixedPort,
    this.tunStack = TunStack.gvisor,
  });

  /// Restores the settings from the map produced by [toJson].
  factory AppSettings.fromJson(JsonMap json) => AppSettings(
        themeMode: AppThemeMode.values.byName(
          JsonRead.stringOr(json, 'themeMode', orElse: 'system'),
        ),
        locale: JsonRead.stringOrNull(json, 'locale'),
        killSwitch: JsonRead.boolean(json, 'killSwitch', orElse: false),
        autoConnect: JsonRead.boolean(json, 'autoConnect', orElse: false),
        startOnBoot: JsonRead.boolean(json, 'startOnBoot', orElse: false),
        hideUnavailable: JsonRead.boolean(
          json,
          'hideUnavailable',
          orElse: false,
        ),
        latencyProbeUrl: JsonRead.stringOr(
          json,
          'latencyProbeUrl',
          orElse: defaultLatencyProbeUrl,
        ),
        ipCheckUrl: JsonRead.stringOr(json, 'ipCheckUrl', orElse: ''),
        logLevel: LogLevel.values.byName(
          JsonRead.stringOr(json, 'logLevel', orElse: 'info'),
        ),
        allowLan: JsonRead.boolean(json, 'allowLan', orElse: false),
        mixedPort: JsonRead.integerOr(
          json,
          'mixedPort',
          orElse: defaultMixedPort,
        ),
        tunStack: TunStack.values.byName(
          JsonRead.stringOr(json, 'tunStack', orElse: 'gvisor'),
        ),
      );

  /// Probe used by the latency test. Always goes *through* the proxy.
  static const String defaultLatencyProbeUrl =
      'http://cp.cloudflare.com/generate_204';

  /// Local mixed (SOCKS + HTTP) inbound port.
  static const int defaultMixedPort = 2080;

  /// The out-of-the-box settings.
  static const AppSettings defaults = AppSettings();

  /// Light, dark or follow the system.
  final AppThemeMode themeMode;

  /// BCP-47 language tag, or `null` to follow the system.
  final String? locale;

  /// Whether traffic is blocked while the tunnel is down.
  final bool killSwitch;

  /// Whether the app connects to the last used node on launch.
  final bool autoConnect;

  /// Whether the app starts with the operating system. Desktop only.
  final bool startOnBoot;

  /// Whether nodes that timed out are hidden from the list.
  ///
  /// Off by default: a timeout does not mean the server is gone, and hiding it
  /// silently is worse than showing it as unreachable.
  final bool hideUnavailable;

  /// URL the latency test requests through the proxy.
  ///
  /// Empty disables the test. The request never leaves the tunnel, so it is
  /// not a rule R1 exception — it is the user's own server being measured.
  final String latencyProbeUrl;

  /// URL the external IP check requests. Empty by default, and it stays empty
  /// until the user fills it in.
  ///
  /// This is exception E-1 to rule R1: it fires only on an explicit button
  /// press, it goes through the tunnel, and its answer is not stored.
  final String ipCheckUrl;

  /// Minimum severity kept in the log.
  final LogLevel logLevel;

  /// Whether the local inbound listens on the LAN instead of loopback.
  final bool allowLan;

  /// Port of the local mixed inbound.
  final int mixedPort;

  /// TUN stack the core uses.
  final TunStack tunStack;

  /// Whether the latency test is switched on at all.
  bool get isLatencyProbeEnabled => latencyProbeUrl.isNotEmpty;

  /// Whether the external IP check is configured.
  bool get isIpCheckEnabled => ipCheckUrl.isNotEmpty;

  /// Returns a copy with the given fields replaced.
  ///
  /// [locale] is the one nullable field; pass an empty string to clear it.
  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? locale,
    bool? killSwitch,
    bool? autoConnect,
    bool? startOnBoot,
    bool? hideUnavailable,
    String? latencyProbeUrl,
    String? ipCheckUrl,
    LogLevel? logLevel,
    bool? allowLan,
    int? mixedPort,
    TunStack? tunStack,
  }) {
    final nextLocale = locale ?? this.locale;
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      locale: nextLocale != null && nextLocale.isEmpty ? null : nextLocale,
      killSwitch: killSwitch ?? this.killSwitch,
      autoConnect: autoConnect ?? this.autoConnect,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      hideUnavailable: hideUnavailable ?? this.hideUnavailable,
      latencyProbeUrl: latencyProbeUrl ?? this.latencyProbeUrl,
      ipCheckUrl: ipCheckUrl ?? this.ipCheckUrl,
      logLevel: logLevel ?? this.logLevel,
      allowLan: allowLan ?? this.allowLan,
      mixedPort: mixedPort ?? this.mixedPort,
      tunStack: tunStack ?? this.tunStack,
    );
  }

  /// Serialises the settings.
  JsonMap toJson() => <String, Object?>{
        'themeMode': themeMode.name,
        'locale': locale,
        'killSwitch': killSwitch,
        'autoConnect': autoConnect,
        'startOnBoot': startOnBoot,
        'hideUnavailable': hideUnavailable,
        'latencyProbeUrl': latencyProbeUrl,
        'ipCheckUrl': ipCheckUrl,
        'logLevel': logLevel.name,
        'allowLan': allowLan,
        'mixedPort': mixedPort,
        'tunStack': tunStack.name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.themeMode == themeMode &&
          other.locale == locale &&
          other.killSwitch == killSwitch &&
          other.autoConnect == autoConnect &&
          other.startOnBoot == startOnBoot &&
          other.hideUnavailable == hideUnavailable &&
          other.latencyProbeUrl == latencyProbeUrl &&
          other.ipCheckUrl == ipCheckUrl &&
          other.logLevel == logLevel &&
          other.allowLan == allowLan &&
          other.mixedPort == mixedPort &&
          other.tunStack == tunStack;

  @override
  int get hashCode => Object.hash(
        themeMode,
        locale,
        killSwitch,
        autoConnect,
        startOnBoot,
        hideUnavailable,
        latencyProbeUrl,
        ipCheckUrl,
        logLevel,
        allowLan,
        mixedPort,
        tunStack,
      );

  @override
  String toString() =>
      'AppSettings(${themeMode.name}, ${locale ?? 'system'}, '
      'killSwitch: $killSwitch, tun: ${tunStack.name})';
}
