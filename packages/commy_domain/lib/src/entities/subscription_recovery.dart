import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/sentinel.dart';
import 'package:commy_domain/src/core/structural.dart';
import 'package:commy_domain/src/entities/recovery_manifest.dart';

/// A change of address the provider signed and the user has not answered.
class PendingDomainChange {
  /// Creates the pending change.
  const PendingDomainChange({required this.manifest, required this.source});

  /// Restores the change from the map produced by [toJson].
  factory PendingDomainChange.fromJson(JsonMap json) => PendingDomainChange(
        manifest: RecoveryManifest.fromJson(
          Map<String, Object?>.from(json['manifest']! as Map<Object?, Object?>),
        ),
        source: RecoverySource.values.asNameMap()[json['source']] ??
            RecoverySource.rendezvous,
      );

  /// What the provider signed.
  final RecoveryManifest manifest;

  /// Where it came from — said in the question, because "your provider's
  /// meeting point" and "the subscription's own address" are not the same
  /// news.
  final RecoverySource source;

  /// Serialises the change.
  JsonMap toJson() => <String, Object?>{
        'manifest': manifest.toJson(),
        'source': source.name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingDomainChange &&
          other.manifest == manifest &&
          other.source == source;

  @override
  int get hashCode => Object.hash(manifest, source);

  @override
  String toString() => 'PendingDomainChange(${manifest.origin.host} via '
      '${source.name})';
}

/// What a subscription knows about its provider's recovery manifests
/// (docs/adr/0019-subscription-domain-recovery.md).
///
/// Present only on a subscription whose provider sent a valid manifest at
/// least once; a subscription without one has `recovery: null`, and no code
/// on the refresh path does anything for it. Nothing here is a secret — no
/// token, no credential; the hosts are the provider's public addresses, the
/// same ones the redacted URL already shows — so it lives in the database
/// beside the rest of the card.
class SubscriptionRecovery {
  /// Creates the state.
  const SubscriptionRecovery({
    required this.id,
    required this.key,
    required this.seq,
    this.nextKey,
    this.issuedAt,
    this.mirrors = const <Uri>[],
    this.rendezvous = const <Uri>[],
    this.name,
    this.pending,
    this.declinedSeq = 0,
    this.lastRendezvousAt,
    this.enabled = true,
  });

  /// Pins [manifest] as the first one seen: trust on first use.
  factory SubscriptionRecovery.pinned(RecoveryManifest manifest) =>
      SubscriptionRecovery(
        id: manifest.id,
        key: manifest.key,
        nextKey: manifest.nextKey,
        seq: manifest.seq,
        issuedAt: manifest.issuedAt,
        mirrors: manifest.mirrors,
        rendezvous: manifest.rendezvous,
        name: manifest.name,
      );

  /// Restores the state from the map produced by [toJson].
  factory SubscriptionRecovery.fromJson(JsonMap json) {
    final pending = json['pending'];
    final last = json['lastRendezvousAt'];
    final issued = json['issuedAt'];
    return SubscriptionRecovery(
      id: '${json['id']}',
      key: '${json['key']}',
      nextKey: json['nextKey'] as String?,
      seq: (json['seq']! as num).toInt(),
      issuedAt: issued is String ? DateTime.tryParse(issued) : null,
      mirrors: _uris(json['mirrors']),
      rendezvous: _uris(json['rendezvous']),
      name: json['name'] as String?,
      pending: pending is Map<Object?, Object?>
          ? PendingDomainChange.fromJson(Map<String, Object?>.from(pending))
          : null,
      declinedSeq: (json['declinedSeq'] as num?)?.toInt() ?? 0,
      lastRendezvousAt: last is String ? DateTime.tryParse(last) : null,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// The provider's project.
  final String id;

  /// The pinned key, base64url.
  final String key;

  /// A key the provider announced it is moving to.
  final String? nextKey;

  /// The last release accepted.
  final int seq;

  /// When the last accepted release was signed.
  final DateTime? issuedAt;

  /// Spare addresses the client may fetch the subscription from.
  final List<Uri> mirrors;

  /// Where the provider's latest manifest may be asked for.
  final List<Uri> rendezvous;

  /// The provider's name.
  final String? name;

  /// A signed change of address waiting for the user's answer.
  final PendingDomainChange? pending;

  /// The highest release the user turned down; not offered again.
  final int declinedSeq;

  /// When a meeting point was last asked — successfully or not.
  final DateTime? lastRendezvousAt;

  /// Whether the user lets this subscription use mirrors and meeting points
  /// at all (exception E-4). Off, a manifest is still read from the
  /// subscription's own answer — that costs no request — but nothing is
  /// fetched from anywhere else.
  final bool enabled;

  /// Whether there is anywhere besides the main address to turn to.
  bool get canReachOut =>
      enabled && (mirrors.isNotEmpty || rendezvous.isNotEmpty);

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` explicitly to a nullable field clears it.
  SubscriptionRecovery copyWith({
    String? id,
    String? key,
    Object? nextKey = Sentinel.unset,
    int? seq,
    Object? issuedAt = Sentinel.unset,
    List<Uri>? mirrors,
    List<Uri>? rendezvous,
    Object? name = Sentinel.unset,
    Object? pending = Sentinel.unset,
    int? declinedSeq,
    Object? lastRendezvousAt = Sentinel.unset,
    bool? enabled,
  }) {
    return SubscriptionRecovery(
      id: id ?? this.id,
      key: key ?? this.key,
      nextKey: identical(nextKey, Sentinel.unset)
          ? this.nextKey
          : nextKey as String?,
      seq: seq ?? this.seq,
      issuedAt: identical(issuedAt, Sentinel.unset)
          ? this.issuedAt
          : issuedAt as DateTime?,
      mirrors: mirrors ?? this.mirrors,
      rendezvous: rendezvous ?? this.rendezvous,
      name: identical(name, Sentinel.unset) ? this.name : name as String?,
      pending: identical(pending, Sentinel.unset)
          ? this.pending
          : pending as PendingDomainChange?,
      declinedSeq: declinedSeq ?? this.declinedSeq,
      lastRendezvousAt: identical(lastRendezvousAt, Sentinel.unset)
          ? this.lastRendezvousAt
          : lastRendezvousAt as DateTime?,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Takes everything [manifest] says, as the new accepted release.
  ///
  /// The key moves along a rotation the old key announced: a manifest signed
  /// by [nextKey] makes it the pinned one. The answer to a pending change of
  /// the same or an older release is no longer needed.
  SubscriptionRecovery adopt(RecoveryManifest manifest) {
    final stillPending = pending;
    return copyWith(
      key: manifest.key,
      nextKey: manifest.nextKey,
      seq: manifest.seq,
      issuedAt: manifest.issuedAt,
      mirrors: manifest.mirrors,
      rendezvous: manifest.rendezvous,
      name: manifest.name ?? name,
      pending: stillPending != null && stillPending.manifest.seq > manifest.seq
          ? stillPending
          : null,
    );
  }

  /// Serialises the state.
  JsonMap toJson() => <String, Object?>{
        'id': id,
        'key': key,
        if (nextKey != null) 'nextKey': nextKey,
        'seq': seq,
        if (issuedAt != null) 'issuedAt': issuedAt!.toUtc().toIso8601String(),
        'mirrors': <String>[for (final mirror in mirrors) mirror.toString()],
        'rendezvous': <String>[
          for (final point in rendezvous) point.toString(),
        ],
        if (name != null) 'name': name,
        if (pending != null) 'pending': pending!.toJson(),
        'declinedSeq': declinedSeq,
        if (lastRendezvousAt != null)
          'lastRendezvousAt': lastRendezvousAt!.toUtc().toIso8601String(),
        'enabled': enabled,
      };

  static List<Uri> _uris(Object? raw) => <Uri>[
        if (raw is List<Object?>)
          for (final item in raw)
            if (Uri.tryParse('$item') case final Uri url) url,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionRecovery &&
          other.id == id &&
          other.key == key &&
          other.nextKey == nextKey &&
          other.seq == seq &&
          other.issuedAt == issuedAt &&
          Structural.listEquals(other.mirrors, mirrors) &&
          Structural.listEquals(other.rendezvous, rendezvous) &&
          other.name == name &&
          other.pending == pending &&
          other.declinedSeq == declinedSeq &&
          other.lastRendezvousAt == lastRendezvousAt &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
        id,
        key,
        nextKey,
        seq,
        issuedAt,
        Structural.listHash(mirrors),
        Structural.listHash(rendezvous),
        name,
        pending,
        declinedSeq,
        lastRendezvousAt,
        enabled,
      );

  @override
  String toString() => 'SubscriptionRecovery($id #$seq, '
      '${mirrors.length} mirrors, ${rendezvous.length} meeting points'
      '${pending == null ? '' : ', pending'}${enabled ? '' : ', off'})';
}
