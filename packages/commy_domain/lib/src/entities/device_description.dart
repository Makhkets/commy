import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';

/// What the device calls itself, for the panel that counts devices.
///
/// Three strings and nothing else. They go out with a subscription request and
/// with nothing else (queue #21, the owner's decision of 2026-09-18), next to
/// the installation identifier a panel uses as the key of its device counter.
///
/// None of them identifies anybody. [os] and [osVersion] are what every
/// browser on the device puts in its user agent; [model] is the marketing name
/// of the hardware, shared by millions of devices and unchanged by a
/// reinstall. The identifier that *is* an identifier lives elsewhere, is a
/// random UUID, and has its own switch — see `DeviceIdentity`.
///
/// A field the platform could not answer is **absent**, not guessed. A header
/// carrying a kernel build string where a panel expects `16` is worse than a
/// header that is not there: the panel stores it and shows it to the user.
class DeviceDescription {
  /// Creates a description.
  const DeviceDescription({required this.os, this.osVersion, this.model});

  /// Reads the shape the platform channel answers with.
  factory DeviceDescription.fromJson(JsonMap json) => DeviceDescription(
        os: JsonRead.stringOr(json, 'os', orElse: ''),
        osVersion: _cleaned(JsonRead.stringOrNull(json, 'osVersion')),
        model: _cleaned(JsonRead.stringOrNull(json, 'model')),
      );

  /// Operating system name, spelled the way panels list devices.
  final String os;

  /// Operating system version as a person reads it, or `null`.
  final String? osVersion;

  /// Marketing name of the hardware, or `null`.
  final String? model;

  /// Serialises the description.
  JsonMap toJson() => <String, Object?>{
        'os': os,
        'osVersion': osVersion,
        'model': model,
      };

  static String? _cleaned(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceDescription &&
          other.os == os &&
          other.osVersion == osVersion &&
          other.model == model;

  @override
  int get hashCode => Object.hash(os, osVersion, model);

  @override
  String toString() => 'DeviceDescription($os $osVersion, $model)';
}
