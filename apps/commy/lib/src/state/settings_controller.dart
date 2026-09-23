import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Writes to settings, routing and DNS.
///
/// Every setter here writes the whole aggregate back rather than patching a
/// column, because the repositories store these as one JSON envelope and a
/// partial write is how two screens end up disagreeing about the truth.
final settingsControllerProvider =
    NotifierProvider<SettingsController, CommyFailure?>(
  SettingsController.new,
);

/// Brings the boot receiver in line with the stored setting, once per launch.
///
/// The receiver's enabled flag belongs to the package manager and the setting
/// to us, and nothing else keeps the two together across a reinstall or a
/// restored backup. Watched from the root like `autoConnectProvider`, and
/// decided off the first settled read for the same reason: a later write
/// goes through [SettingsController.setStartOnBoot], which does its own
/// platform call.
final startOnBootSyncProvider = Provider<void>((ref) {
  var applied = false;
  void consider() {
    if (applied) {
      return;
    }
    final settings = ref.read(settingsProvider).value;
    if (settings == null) {
      return;
    }
    applied = true;
    unawaited(
      ref
          .read(systemSettingsProvider)
          .setStartOnBoot(enabled: settings.startOnBoot),
    );
  }

  ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, __) => consider());
  consider();
});

/// The write side of the settings screens.
class SettingsController extends Notifier<CommyFailure?> {
  /// The probe used when the user turns the IP check on.
  ///
  /// Exception E-1 of docs/09-security-privacy.md. It is stored rather than
  /// hardcoded at the call site so that turning the feature off leaves an
  /// empty string — and an empty string is what `AppSettings.isIpCheckEnabled`
  /// reads as "never call anybody".
  static const String defaultIpCheckUrl = 'https://ipinfo.io/json';

  @override
  CommyFailure? build() => null;

  /// Stores [settings] wholesale.
  Future<void> save(AppSettings settings) async {
    final result = await ref.read(settingsRepositoryProvider).write(settings);
    state = result.failureOrNull;
  }

  /// Turns exception E-1, the on-demand IP check, on or off.
  Future<void> setIpCheck({required bool enabled}) async {
    final current = await _settings();
    await save(
      current.copyWith(ipCheckUrl: enabled ? defaultIpCheckUrl : ''),
    );
  }

  /// Turns "connect on boot" on or off.
  ///
  /// Two writes, and the order matters: the setting first, the platform
  /// second, and the second only if the first went through. A boot receiver
  /// enabled for a setting that failed to save would be the very defect this
  /// method exists to close — a switch and a mechanism that disagree.
  Future<void> setStartOnBoot({required bool enabled}) async {
    await save((await _settings()).copyWith(startOnBoot: enabled));
    if (state != null) {
      return;
    }
    await ref.read(systemSettingsProvider).setStartOnBoot(enabled: enabled);
  }

  /// Hides or shows servers that failed their last probe.
  Future<void> setHideUnavailable({required bool enabled}) async {
    await save((await _settings()).copyWith(hideUnavailable: enabled));
  }

  /// Switches the device identifier (HWID) on subscription requests.
  ///
  /// Read by `StoredDeviceIdentity` on the next fetch; nothing is sent, and
  /// nothing is even generated, while it is off.
  Future<void> setSendDeviceId({required bool enabled}) async {
    await save((await _settings()).copyWith(sendDeviceId: enabled));
  }

  /// Forgets the device identifier; the next subscription request makes a new
  /// one. Returns whether the store let go of it.
  Future<bool> resetDeviceId() async {
    final result = await ref.read(deviceIdentityProvider).reset();
    return result.isOk;
  }

  /// Changes how the servers inside each list are ordered.
  Future<void> setNodeSort(NodeSort sort) async {
    await save((await _settings()).copyWith(nodeSort: sort));
  }

  /// Switches the theme.
  Future<void> setThemeMode(AppThemeMode mode) async {
    await save((await _settings()).copyWith(themeMode: mode));
  }

  /// Switches the language. An empty string means "follow the system".
  Future<void> setLocale(String? locale) async {
    await save((await _settings()).copyWith(locale: locale ?? ''));
  }

  /// Raises or lowers how much the core is asked to log.
  Future<void> setLogLevel(LogLevel level) async {
    await save((await _settings()).copyWith(logLevel: level));
  }

  /// Chooses how servers are timed. Takes effect on the next measurement; a
  /// running tunnel has nothing to reload for it.
  Future<void> setPingMethod(PingMethod method) async {
    await save((await _settings()).copyWith(pingMethod: method));
  }

  /// Stores a whole routing policy.
  Future<void> saveRouting(RoutingPolicy policy) async {
    final result = await ref.read(routingRepositoryProvider).write(policy);
    state = result.failureOrNull;
  }

  /// Switches between global, rule-based and direct routing.
  Future<void> setRoutingMode(RoutingMode mode) async {
    await saveRouting((await _routing()).copyWith(mode: mode));
  }

  /// Turns exception E-2, the geoip and geosite rule sets, on or off.
  ///
  /// Rule sets are only meaningful in rule mode, so the switch that governs
  /// them is the mode: turning it off drops the app back to a global proxy
  /// that needs no downloaded lists at all.
  Future<void> setRuleSetsEnabled({required bool enabled}) async {
    await setRoutingMode(enabled ? RoutingMode.rules : RoutingMode.global);
  }

  /// Sets where exception E-2 fetches its rule sets from.
  ///
  /// An empty template is a valid answer and switches the exception off: a
  /// user who wants the request to be impossible rather than merely unused
  /// clears the field, and the buttons that would make it go away.
  Future<void> setRuleSetSource(String template) async {
    final settings = await _settings();
    await save(settings.copyWith(ruleSetSource: template.trim()));
  }

  /// Turns exception E-3, the advertising block lists, on or off.
  Future<void> setBlockAds({required bool enabled}) async {
    await saveRouting((await _routing()).copyWith(blockAds: enabled));
  }

  /// Keeps the local network off the tunnel, or does not.
  Future<void> setBypassLan({required bool enabled}) async {
    await saveRouting((await _routing()).copyWith(bypassLan: enabled));
  }

  /// Adds a rule at the end of the list, just above the final outcome.
  Future<void> addRule({
    required String matcher,
    required RuleAction action,
  }) async {
    final trimmed = matcher.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final policy = await _routing();
    final rule = RoutingRule(
      id: ref.read(idGeneratorProvider).newId(),
      matcher: trimmed,
      action: action,
      sortIndex: policy.rules.length,
    );
    await saveRouting(
      policy.copyWith(rules: <RoutingRule>[...policy.rules, rule]),
    );
  }

  /// Removes a rule.
  Future<void> removeRule(String id) async {
    final policy = await _routing();
    await saveRouting(
      policy.copyWith(
        rules: <RoutingRule>[
          for (final rule in policy.rules)
            if (rule.id != id) rule,
        ],
      ),
    );
  }

  /// Moves the rule at [from] to [to]. Order is priority, so this is a
  /// semantic change, not a cosmetic one.
  ///
  /// [to] is the destination index **after** the rule has been lifted out,
  /// which is what `ReorderableListView.onReorderItem` hands over.
  Future<void> moveRule(int from, int to) async {
    final policy = await _routing();
    final rules = List<RoutingRule>.of(policy.rules);
    if (from < 0 || from >= rules.length) {
      return;
    }
    final moved = rules.removeAt(from);
    rules.insert(to.clamp(0, rules.length), moved);
    await saveRouting(
      policy.copyWith(
        rules: <RoutingRule>[
          for (var index = 0; index < rules.length; index++)
            rules[index].copyWith(sortIndex: index),
        ],
      ),
    );
  }

  /// Stores DNS settings.
  Future<void> saveDns(DnsSettings settings) async {
    final result = await ref.read(routingRepositoryProvider).writeDns(settings);
    state = result.failureOrNull;
  }

  /// Puts routing and DNS back as they were after install: "reset network".
  ///
  /// The mode, the user's rules, per-app routing, ad blocking, the LAN switch
  /// and every DNS setting return to their defaults. Servers and
  /// subscriptions are not network settings and stay where they are. A
  /// running tunnel takes the change the way it takes any routing edit —
  /// `liveReloadProvider` reloads it, once for both writes.
  ///
  /// Returns whether both writes went through.
  Future<bool> resetNetwork() async {
    await saveRouting(RoutingPolicy.defaults);
    if (state != null) {
      return false;
    }
    await saveDns(DnsSettings.defaults);
    return state == null;
  }

  /// Puts the app's own settings back as they were after install.
  ///
  /// Theme, language, connecting on launch and on boot, the silence panel's
  /// exceptions, the log level and the rest of [AppSettings]. Servers,
  /// subscriptions, routing and DNS stay — they have a reset of their own —
  /// and so does the device identifier, which has its own row. The boot
  /// receiver is brought in line with the restored setting, the way
  /// [setStartOnBoot] does it.
  ///
  /// Returns whether the write went through.
  Future<bool> resetAppSettings() async {
    await save(AppSettings.defaults);
    if (state != null) {
      return false;
    }
    await ref
        .read(systemSettingsProvider)
        .setStartOnBoot(enabled: AppSettings.defaults.startOnBoot);
    return true;
  }

  /// Clears the last failure once it has been shown.
  void clear() => state = null;

  Future<AppSettings> _settings() async {
    final result = await ref.read(settingsRepositoryProvider).read();
    return result.valueOrNull ?? AppSettings.defaults;
  }

  Future<RoutingPolicy> _routing() async {
    final result = await ref.read(routingRepositoryProvider).read();
    return result.valueOrNull ?? RoutingPolicy.defaults;
  }
}
