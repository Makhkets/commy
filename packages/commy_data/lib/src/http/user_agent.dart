/// The identification Commy sends when it fetches a subscription.
///
/// This is a product decision with teeth, not a formality. Panels — Marzban,
/// Remnawave, x-ui, 3x-ui — inspect the User-Agent and serve a *different
/// format* per client: base64 to one, Clash YAML to another, sing-box JSON to a
/// third. Send the wrong string and a perfectly good subscription looks broken.
///
/// docs/06-data-model.md settles the default: we go with the honest
/// `Commy/<version>` and do not masquerade as somebody else's client. Panels
/// that only answer known clients are handled per subscription, through
/// `Subscription.userAgentOverride`, which the user sets and can see — the
/// presets below exist to make that one tap rather than an internet search.
abstract final class CommyUserAgent {
  /// Product name used in the honest User-Agent.
  static const String product = 'Commy';

  /// The honest identification for [version], for example `Commy/1.0.0`.
  static String honest(String version) => '$product/$version';

  /// Fallback used before the real version is known.
  ///
  /// The composition root should replace it with `honest(packageInfo.version)`
  /// at startup; shipping a hardcoded version number here would go stale on the
  /// first release.
  static const String fallback = '$product/dev';

  /// Presets offered in the "User-Agent" field of a subscription.
  ///
  /// Every one of these is a real, widely deployed client string. They are
  /// offered, never applied silently.
  static const Map<String, String> presets = <String, String>{
    'v2rayNG': 'v2rayNG/1.9.16',
    'v2rayN': 'v2rayN/7.0.1',
    'Clash': 'ClashforWindows/0.20.39',
    'Clash.Meta': 'clash-verge/v2.0.3',
    'sing-box': 'sing-box/1.11.0',
    'Hiddify': 'HiddifyNext/2.5.7',
    'Streisand': 'Streisand/1.6.44',
  };

  /// The preset most panels recognise, for the "nothing else works" case.
  ///
  /// Not a default. A subscription only sends this once the user picked it.
  static const String widelyAcceptedPreset = 'v2rayNG/1.9.16';
}
