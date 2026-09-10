import 'package:commy_core/src/android/installed_app.dart';
import 'package:commy_core/src/wire/wire_channels.dart';
import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_methods.dart';
import 'package:flutter/services.dart';

/// The system-side switches Commy can flip but cannot replace.
///
/// Three so far. [openVpnSettings] exists for a reason worth stating: an
/// application-level kill switch is a promise an application cannot keep. If
/// the process is killed — by the user, by the system, by an out-of-memory
/// reaper — there is nothing left running to block traffic with. Android's own
/// "Always-on VPN" plus "Block connections without VPN" is enforced by the
/// framework and survives all three, so the honest thing is to name it, say it
/// belongs to the system, and offer to open it.
///
/// Kept out of `CoreClient`: that port is the tunnel, shared by five
/// platforms, and none of this is tunnel state.
class SystemSettings {
  /// Creates the accessor over the shared method channel.
  const SystemSettings({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(WireChannels.method);

  final MethodChannel _channel;

  /// Opens the system VPN settings screen.
  ///
  /// Returns `false` when the platform has no such screen — every desktop, and
  /// the Android images that hide it. Never throws: this is a convenience on a
  /// settings row, and a settings row must not be able to crash the app.
  Future<bool> openVpnSettings() async {
    try {
      await _channel.invokeMethod<void>(WireMethods.openVpnSettings);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Turns "connect on boot" on or off at the platform level.
  ///
  /// The setting itself lives in the settings repository; this call is what
  /// makes the boot receiver agree with it. Returns `false` where there is
  /// no such receiver — every desktop — and never throws, for the same reason
  /// as [openVpnSettings].
  Future<bool> setStartOnBoot({required bool enabled}) async {
    try {
      await _channel.invokeMethod<void>(WireMethods.setStartOnBoot, enabled);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// The apps the per-app routing picker can offer, sorted for display.
  ///
  /// Empty on every platform that does not route by application, which is all
  /// of them but Android — and empty, not an exception, because "this device
  /// has no such list" is an answer the screen draws an empty state for.
  ///
  /// Sorted here rather than on the Kotlin side so the order is the same
  /// wherever the list comes from: by label, case-insensitively, with the
  /// system apps after the ones the user installed. Nobody scrolls past forty
  /// Google packages looking for their browser.
  Future<List<InstalledApp>> installedApps() async {
    final String raw;
    try {
      raw = await _channel.invokeMethod<String>(WireMethods.installedApps) ??
          '[]';
    } on MissingPluginException {
      return const <InstalledApp>[];
    } on PlatformException {
      return const <InstalledApp>[];
    }

    final apps = <InstalledApp>[
      for (final entry in WireJson.objectList(raw, WireMethods.installedApps))
        InstalledApp.fromJson(entry),
    ]
      ..removeWhere((app) => app.packageName.isEmpty)
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) {
          return a.isSystem ? 1 : -1;
        }
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return apps;
  }
}
