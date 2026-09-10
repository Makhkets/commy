import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';

/// One application the per-app routing picker can offer.
///
/// Lives here rather than in `commy_domain` on purpose: the domain stores a
/// list of package names and knows nothing about where they came from, which
/// is what lets the same `RoutingPolicy` mean something on a platform that has
/// no application list at all.
@immutable
class InstalledApp {
  /// Creates the entry.
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.isSystem = false,
  });

  /// Reads one entry off the wire.
  ///
  /// A missing label falls back to the package name. Some system packages
  /// genuinely have none, and a row that reads as an empty string is worse
  /// than a row that reads as `com.android.something`.
  factory InstalledApp.fromJson(JsonMap json) {
    final packageName = WireJson.stringOr(json, WireKeys.package, orElse: '');
    final label = WireJson.stringOr(json, WireKeys.label, orElse: '');
    return InstalledApp(
      packageName: packageName,
      label: label.isEmpty ? packageName : label,
      isSystem: json[WireKeys.isSystem] == true,
    );
  }

  /// Android application id, e.g. `org.mozilla.firefox`.
  final String packageName;

  /// What the launcher calls it, in the device's language.
  final String label;

  /// Whether it shipped with the system image.
  final bool isSystem;

  /// Whether [query] matches the name or the package, case-insensitively.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(needle) ||
        packageName.toLowerCase().contains(needle);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstalledApp &&
          other.packageName == packageName &&
          other.label == label &&
          other.isSystem == isSystem;

  @override
  int get hashCode => Object.hash(packageName, label, isSystem);

  @override
  String toString() => 'InstalledApp($packageName, $label)';
}
