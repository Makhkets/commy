import 'dart:async';

import 'package:commy_core/src/android/installed_app.dart';
import 'package:commy_core/src/wire/probe_codec.dart';
import 'package:commy_core/src/wire/url_test_codec.dart';
import 'package:commy_core/src/wire/wire_channels.dart';
import 'package:commy_core/src/wire/wire_format_exception.dart';
import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_methods.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/services.dart';

/// The system-side switches Commy can flip but cannot replace, and the one
/// measurement `dart:io` cannot make.
///
/// Four switches so far. [openVpnSettings] exists for a reason worth stating:
/// an application-level kill switch is a promise an application cannot keep. If
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

  /// How long [deviceInfo] waits for the platform before giving up.
  ///
  /// Generous for three strings read out of `Build`, and short enough that a
  /// platform which never answers cannot hold a subscription refresh.
  static const Duration answerWithin = Duration(seconds: 2);

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

  /// What the device calls itself, or `null` where nothing can say.
  ///
  /// Exists so that a dependency does not. A panel that limits devices per
  /// subscription lists them by name and version, and `dart:io` answers
  /// neither honestly: `Platform.operatingSystemVersion` on Android is a
  /// kernel build string where the panel wants `16`, and there is no model at
  /// all. `device_info_plus` would bring native code along for three strings
  /// (CLAUDE.md §7, point 2).
  ///
  /// Null on every platform without the method, and null rather than a
  /// half-filled description: the caller sends the headers it has, and a
  /// header holding a guess is worse than one that is absent, because the
  /// panel stores it and shows it back to the user.
  Future<DeviceDescription?> deviceInfo() async {
    final String? raw;
    try {
      raw = await _channel
          .invokeMethod<String>(WireMethods.deviceInfo)
          // Bounded, because the caller is a subscription refresh and these
          // two headers are optional to it. A platform that answers nothing
          // must cost the headers, not the refresh.
          .timeout(answerWithin, onTimeout: () => null);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return DeviceDescription.fromJson(
        WireJson.object(raw, WireMethods.deviceInfo),
      );
    } on Object {
      return null;
    }
  }

  /// One ICMP echo to [host]: the round trip, or `null`.
  ///
  /// The "Ping" setting's ICMP method. `dart:io` has no ICMP socket, and
  /// Android lets every app open an unprivileged one, so the platform sends
  /// it. Null when nothing came back within [timeout], and on every platform
  /// without the method — never an exception, because a server that does not
  /// answer an echo is a measurement, and many do not.
  Future<Duration?> ping(String host, {required Duration timeout}) async {
    try {
      final raw = await _channel
          .invokeMethod<String>(
            WireMethods.ping,
            ProbeCodec.encodePing(host, timeout: timeout),
          )
          // The platform has its own deadline; this one is for a platform
          // that never answers at all.
          .timeout(timeout + answerWithin, onTimeout: () => null);
      return UrlTestCodec.decodeDelay(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on WireFormatException {
      return null;
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
