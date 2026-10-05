import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/structural.dart';
import 'package:commy_domain/src/entities/routing.dart';

/// A named routing setup the user can switch to in one tap: home, work,
/// travel — "everything through the server" next to "Russian sites direct"
/// (D10 of the 1.0 release, docs/07-roadmap.md).
///
/// It holds a whole [RoutingPolicy]: mode, rules, LAN bypass, ad blocking and
/// the per-app list. DNS stays global — a resolver is a property of the
/// network the phone is on, not of a set of rules, and switching it with a
/// profile would be the surprise rather than the feature.
class RoutingProfile {
  /// Creates a profile.
  const RoutingProfile({
    required this.id,
    required this.name,
    required this.policy,
  });

  /// Restores a profile from the map produced by [toJson].
  factory RoutingProfile.fromJson(JsonMap json) => RoutingProfile(
        id: '${json['id']}',
        name: '${json['name']}',
        policy: RoutingPolicy.fromJson(
          Map<String, Object?>.from(json['policy']! as Map<Object?, Object?>),
        ),
      );

  /// Stable identifier.
  final String id;

  /// The name on the chip.
  final String name;

  /// The routing this profile stands for.
  final RoutingPolicy policy;

  /// Returns a copy with the given fields replaced.
  RoutingProfile copyWith({String? name, RoutingPolicy? policy}) =>
      RoutingProfile(
        id: id,
        name: name ?? this.name,
        policy: policy ?? this.policy,
      );

  /// Serialises the profile.
  JsonMap toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'policy': policy.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutingProfile &&
          other.id == id &&
          other.name == name &&
          other.policy == policy;

  @override
  int get hashCode => Object.hash(id, name, policy);

  @override
  String toString() => 'RoutingProfile($id, $name)';
}

/// Every routing profile, and which one the live policy belongs to.
///
/// The live policy — the rules table and its envelope, what the routing
/// screen edits and the builder reads — stays the single source of truth for
/// what is in force. A profile is a stored copy; the active one's copy is
/// refreshed from the live policy each time the user leaves it, so edits made
/// on the routing screen are never lost by a switch.
///
/// Empty means the feature is not in use: one implicit setup, the live one,
/// exactly as before profiles existed.
class RoutingProfiles {
  /// Creates the list.
  const RoutingProfiles({
    this.profiles = const <RoutingProfile>[],
    this.activeId,
  });

  /// Restores the list from the map produced by [toJson]. A profile that
  /// does not read is left out rather than costing the rest.
  factory RoutingProfiles.fromJson(JsonMap json) {
    final raw = json['profiles'];
    final profiles = <RoutingProfile>[];
    if (raw is List<Object?>) {
      for (final item in raw) {
        if (item is! Map<Object?, Object?>) {
          continue;
        }
        try {
          profiles.add(
            RoutingProfile.fromJson(Map<String, Object?>.from(item)),
          );
          // A profile from a newer Commy throws whatever its parser throws.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
      }
    }
    final active = json['activeId'];
    return RoutingProfiles(
      profiles: profiles,
      activeId: active is String && profiles.any((p) => p.id == active)
          ? active
          : (profiles.isEmpty ? null : profiles.first.id),
    );
  }

  /// Nothing set up.
  static const RoutingProfiles empty = RoutingProfiles();

  /// The longest name a profile may have.
  static const int maxName = 40;

  /// The profiles, in the order the user made them.
  final List<RoutingProfile> profiles;

  /// The profile the live policy belongs to.
  final String? activeId;

  /// Whether the user has set up any.
  bool get isInUse => profiles.isNotEmpty;

  /// The active profile, if there is one.
  RoutingProfile? get active {
    for (final profile in profiles) {
      if (profile.id == activeId) {
        return profile;
      }
    }
    return null;
  }

  /// [live] saved under [name] as a new profile, made active.
  ///
  /// The first time, the setup the user had until now is kept as a profile
  /// too, under [currentName]: otherwise saving a copy would be the only way
  /// back to it.
  RoutingProfiles saveAs({
    required RoutingPolicy live,
    required String name,
    required String id,
    required String currentName,
    required String currentId,
  }) {
    final kept = isInUse
        ? _synced(live)
        : <RoutingProfile>[
            RoutingProfile(id: currentId, name: currentName, policy: live),
          ];
    return RoutingProfiles(
      profiles: <RoutingProfile>[
        ...kept,
        RoutingProfile(id: id, name: _clip(name), policy: live),
      ],
      activeId: id,
    );
  }

  /// A profile brought in from outside (a shared link), made active.
  ///
  /// Like [saveAs], the setup in force until now is kept first.
  RoutingProfiles add({
    required RoutingPolicy live,
    required RoutingProfile profile,
    required String currentName,
    required String currentId,
  }) {
    final kept = isInUse
        ? _synced(live)
        : <RoutingProfile>[
            RoutingProfile(id: currentId, name: currentName, policy: live),
          ];
    return RoutingProfiles(
      profiles: <RoutingProfile>[
        ...kept,
        profile.copyWith(name: _clip(profile.name)),
      ],
      activeId: profile.id,
    );
  }

  /// Switches to [id]: the policy it stands for, and the list with the
  /// profile being left refreshed from [live]. `null` when there is no such
  /// profile or it is already the active one.
  ({RoutingProfiles profiles, RoutingPolicy live})? switchTo(
    String id, {
    required RoutingPolicy live,
  }) {
    if (id == activeId) {
      return null;
    }
    final synced = _synced(live);
    for (final profile in synced) {
      if (profile.id == id) {
        return (
          profiles: RoutingProfiles(profiles: synced, activeId: id),
          live: profile.policy,
        );
      }
    }
    return null;
  }

  /// [id] under a new name.
  RoutingProfiles rename(String id, String name) {
    final clipped = _clip(name);
    if (clipped.isEmpty) {
      return this;
    }
    return RoutingProfiles(
      profiles: <RoutingProfile>[
        for (final profile in profiles)
          profile.id == id ? profile.copyWith(name: clipped) : profile,
      ],
      activeId: activeId,
    );
  }

  /// Without [id]. The active profile cannot be removed — switch first — and
  /// neither can the last one: removing it would leave a list whose live
  /// policy belongs to nothing. `null` when refused.
  RoutingProfiles? remove(String id) {
    if (id == activeId || profiles.length <= 1) {
      return null;
    }
    if (!profiles.any((profile) => profile.id == id)) {
      return null;
    }
    return RoutingProfiles(
      profiles: <RoutingProfile>[
        for (final profile in profiles)
          if (profile.id != id) profile,
      ],
      activeId: activeId,
    );
  }

  /// The profiles with the active one's copy replaced by [live].
  List<RoutingProfile> _synced(RoutingPolicy live) => <RoutingProfile>[
        for (final profile in profiles)
          profile.id == activeId ? profile.copyWith(policy: live) : profile,
      ];

  static String _clip(String name) {
    final trimmed = name.trim();
    return trimmed.length > maxName
        ? trimmed.substring(0, maxName).trim()
        : trimmed;
  }

  /// Serialises the list.
  JsonMap toJson() => <String, Object?>{
        'profiles': <JsonMap>[for (final p in profiles) p.toJson()],
        'activeId': activeId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutingProfiles &&
          other.activeId == activeId &&
          Structural.listEquals(other.profiles, profiles);

  @override
  int get hashCode => Object.hash(activeId, Structural.listHash(profiles));

  @override
  String toString() => 'RoutingProfiles(${profiles.length}, active: $activeId)';
}
