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
    this.autoConnect = false,
    this.autoSelect = false,
    this.startOnBoot = false,
    this.hideUnavailable = false,
    this.latencyProbeUrl = defaultLatencyProbeUrl,
    this.ipCheckUrl = '',
    this.ruleSetSource = defaultRuleSetSource,
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
        autoConnect: JsonRead.boolean(json, 'autoConnect', orElse: false),
        autoSelect: JsonRead.boolean(json, 'autoSelect', orElse: false),
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
        ruleSetSource: JsonRead.stringOr(
          json,
          'ruleSetSource',
          orElse: defaultRuleSetSource,
        ),
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

  /// Where the geoip and geosite rule sets are downloaded from.
  ///
  /// A template, not a URL: [ruleSetTagToken] is replaced with the tag being
  /// fetched. Exception E-2 requires the source to be the user's to change,
  /// their own mirror included, so this is a default rather than a constant —
  /// and nothing is ever fetched from it except on an explicit button press.
  static const String defaultRuleSetSource =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/'
      '{tag}.srs';

  /// The placeholder [ruleSetSource] substitutes the rule set tag into.
  static const String ruleSetTagToken = '{tag}';

  /// Local mixed (SOCKS + HTTP) inbound port.
  static const int defaultMixedPort = 2080;

  /// The out-of-the-box settings.
  static const AppSettings defaults = AppSettings();

  /// Light, dark or follow the system.
  final AppThemeMode themeMode;

  /// BCP-47 language tag, or `null` to follow the system.
  final String? locale;

  // There is deliberately no `killSwitch` here.
  //
  // It used to exist, was written by a switch on the settings screen, and was
  // read by nothing: no builder put it in the configuration and no Kotlin
  // consulted it. That made it worse than a missing feature — it was a claim
  // about traffic being blocked, in the one part of the app whose job is to
  // be exact about what happens to traffic (docs/09-security-privacy.md).
  //
  // The guarantee itself belongs to the operating system. Android enforces
  // "Always-on VPN" + "Block connections without VPN" in the framework, so it
  // survives the app being killed, which is precisely the case an in-process
  // kill switch cannot cover. The settings screen now names that and offers to
  // open it. Old stored settings may still carry the key; `fromJson` ignores
  // what it does not read.

  /// Whether the app connects to the last used node on launch.
  final bool autoConnect;

  /// Whether the core picks the node instead of the user.
  ///
  /// Auto is a **group**, not a node: the core measures every member against
  /// [latencyProbeUrl] and keeps traffic on the quickest one
  /// (docs/05-ux-flows.md, scenario 4). It lives here rather than next to the
  /// selected node id because the two are different answers to the same
  /// question — the id says which server leads the list, this says whether the
  /// core is allowed to overrule it — and because the configuration builder
  /// reads the settings, not the selection.
  ///
  /// A group of one is not a choice, so the builder ignores this while there
  /// is a single stored node. The setting survives that: import a second
  /// server and Auto is on again, which is what the user asked for.
  final bool autoSelect;

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

  /// Template the geoip and geosite sets are downloaded from.
  ///
  /// This is exception E-2: it fires only on an explicit button press, the
  /// source is the user's to change, and the answer is cached on disk so
  /// nothing has a reason to fetch it again. See [defaultRuleSetSource].
  final String ruleSetSource;

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

  /// Whether rule sets can be downloaded at all.
  ///
  /// An empty source is a deliberate setting, not a broken one: a user who
  /// wants no such request available clears the field, and the button that
  /// would make it goes away with it.
  bool get isRuleSetSourceEnabled => ruleSetSource.trim().isNotEmpty;

  /// The URL [tag] is fetched from, or `null` when no source is configured.
  Uri? ruleSetUrl(String tag) {
    final template = ruleSetSource.trim();
    if (template.isEmpty) {
      return null;
    }
    return Uri.tryParse(template.replaceAll(ruleSetTagToken, tag));
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// [locale] is the one nullable field; pass an empty string to clear it.
  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? locale,
    bool? autoConnect,
    bool? autoSelect,
    bool? startOnBoot,
    bool? hideUnavailable,
    String? latencyProbeUrl,
    String? ipCheckUrl,
    String? ruleSetSource,
    LogLevel? logLevel,
    bool? allowLan,
    int? mixedPort,
    TunStack? tunStack,
  }) {
    final nextLocale = locale ?? this.locale;
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      locale: nextLocale != null && nextLocale.isEmpty ? null : nextLocale,
      autoConnect: autoConnect ?? this.autoConnect,
      autoSelect: autoSelect ?? this.autoSelect,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      hideUnavailable: hideUnavailable ?? this.hideUnavailable,
      latencyProbeUrl: latencyProbeUrl ?? this.latencyProbeUrl,
      ipCheckUrl: ipCheckUrl ?? this.ipCheckUrl,
      ruleSetSource: ruleSetSource ?? this.ruleSetSource,
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
        'autoConnect': autoConnect,
        'autoSelect': autoSelect,
        'startOnBoot': startOnBoot,
        'hideUnavailable': hideUnavailable,
        'latencyProbeUrl': latencyProbeUrl,
        'ipCheckUrl': ipCheckUrl,
        'ruleSetSource': ruleSetSource,
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
          other.autoConnect == autoConnect &&
          other.autoSelect == autoSelect &&
          other.startOnBoot == startOnBoot &&
          other.hideUnavailable == hideUnavailable &&
          other.latencyProbeUrl == latencyProbeUrl &&
          other.ipCheckUrl == ipCheckUrl &&
          other.ruleSetSource == ruleSetSource &&
          other.logLevel == logLevel &&
          other.allowLan == allowLan &&
          other.mixedPort == mixedPort &&
          other.tunStack == tunStack;

  @override
  int get hashCode => Object.hash(
        themeMode,
        locale,
        autoConnect,
        autoSelect,
        startOnBoot,
        hideUnavailable,
        latencyProbeUrl,
        ipCheckUrl,
        ruleSetSource,
        logLevel,
        allowLan,
        mixedPort,
        tunStack,
      );

  @override
  String toString() =>
      'AppSettings(${themeMode.name}, ${locale ?? 'system'}, '
      'tun: ${tunStack.name})';
}
