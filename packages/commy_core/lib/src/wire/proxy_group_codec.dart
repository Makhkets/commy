import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes the result of `proxies()`.
///
/// The wire shape carries more than the domain does — `urlTestDelay`,
/// `selectable`, the type of each member. All of it is dropped right here: the
/// domain `ProxyGroup` does not have those fields and inventing a parallel
/// model to hold them would put two sources of truth on screen. They stay in
/// the protocol because they cost Kotlin nothing and a bulk latency sweep will
/// want them (`docs/wire-protocol.md`, "proxies()").
abstract final class ProxyGroupCodec {
  /// Group kind assumed when the native side omitted `type`.
  ///
  /// The field is required by the protocol, so a missing one is a bug on the
  /// other side. Of the two ways to be wrong, assuming `selector` lets the user
  /// try to switch and lets the core refuse — recoverable, and visible. The
  /// other way greys the switcher out forever with no error anywhere, and that
  /// is the kind of bug that survives a release.
  static const String defaultType = 'selector';

  /// Decodes the `proxies()` result.
  ///
  /// A missing or empty payload is an empty list, which is also what a stopped
  /// core answers — not an error.
  static List<ProxyGroup> decodeList(Object? raw) {
    if (raw == null) {
      return const <ProxyGroup>[];
    }
    final result = <ProxyGroup>[];
    for (final json in WireJson.objectList(raw, 'proxies() result')) {
      final tag = WireJson.stringOrNull(json, WireKeys.tag);
      if (tag == null) {
        continue;
      }
      result.add(
        ProxyGroup(
          tag: tag,
          type: WireJson.stringOr(json, WireKeys.type, orElse: defaultType),
          now: WireJson.stringOrNull(json, WireKeys.selected),
          all: _members(json),
        ),
      );
    }
    return result;
  }

  /// Encodes [group] back into the wire shape.
  ///
  /// [delays] optionally supplies a measured round trip per member, in
  /// milliseconds, so a fake or a test can produce a payload that looks like
  /// the real one down to `urlTestDelay`.
  static JsonMap encode(ProxyGroup group, {Map<String, int>? delays}) =>
      <String, Object?>{
        WireKeys.tag: group.tag,
        WireKeys.type: group.type,
        WireKeys.selected: group.now,
        WireKeys.items: <Object?>[
          for (final member in group.all)
            <String, Object?>{
              WireKeys.tag: member,
              WireKeys.urlTestDelay: delays?[member] ?? 0,
            },
        ],
      };

  static List<String> _members(JsonMap json) {
    final raw = json[WireKeys.items];
    if (raw is! List<Object?>) {
      return const <String>[];
    }
    final tags = <String>[];
    for (final item in raw) {
      final member = WireJson.asMap(item);
      final tag = member == null
          ? null
          : WireJson.stringOrNull(member, WireKeys.tag);
      if (tag != null) {
        tags.add(tag);
      }
    }
    return tags;
  }
}
