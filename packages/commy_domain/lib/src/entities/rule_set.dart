import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';

/// One geoip or geosite rule set that is on disk.
///
/// The tag is what a routing rule names — `geosite-ru`, `geoip-private` — and
/// what the generated configuration points at. Everything else on this class
/// exists so the screen can say what was downloaded and when, because a file
/// the user cannot see the age of is a file they cannot decide to refresh.
class RuleSet {
  /// Creates the record.
  const RuleSet({
    required this.tag,
    required this.sizeBytes,
    required this.updatedAt,
  });

  /// Restores the record from the map produced by [toJson].
  factory RuleSet.fromJson(JsonMap json) => RuleSet(
        tag: JsonRead.string(json, 'tag'),
        sizeBytes: JsonRead.integerOr(json, 'sizeBytes', orElse: 0),
        updatedAt:
            JsonRead.dateTimeOrNull(json, 'updatedAt') ?? DateTime.utc(1970),
      );

  /// Tag the routing rules refer to.
  final String tag;

  /// Size of the `.srs` file on disk.
  final int sizeBytes;

  /// When it was last downloaded.
  final DateTime updatedAt;

  /// How old the file is at [now].
  Duration ageAt(DateTime now) => now.difference(updatedAt);

  /// Returns a copy with the given fields replaced.
  RuleSet copyWith({String? tag, int? sizeBytes, DateTime? updatedAt}) =>
      RuleSet(
        tag: tag ?? this.tag,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Serialises the record.
  JsonMap toJson() => <String, Object?>{
        'tag': tag,
        'sizeBytes': sizeBytes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleSet &&
          other.tag == tag &&
          other.sizeBytes == sizeBytes &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(tag, sizeBytes, updatedAt);

  @override
  String toString() => 'RuleSet($tag, $sizeBytes bytes)';
}
