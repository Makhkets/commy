import 'dart:convert';

import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/structural.dart';

/// Where a manifest reached the client from.
///
/// The trust rules of docs/adr/0019-subscription-domain-recovery.md turn on
/// it: only the subscription's own address may pin a key or change anything
/// silently, because it already controls the subscription whole.
enum RecoverySource {
  /// The subscription's own address, the one the user imported or accepted.
  primary,

  /// A spare address the provider announced in a signed manifest.
  mirror,

  /// A meeting point that serves the provider's latest manifest.
  rendezvous,
}

/// A subscription provider's signed statement of where its subscription
/// lives (docs/adr/0019-subscription-domain-recovery.md).
///
/// Built only by [SignedManifest.parse], which checks the shape; whether the
/// signature holds is a separate step (`ManifestReader`). An instance says
/// nothing about trust on its own.
class RecoveryManifest {
  /// Creates a manifest. Use [SignedManifest.parse] for anything received.
  const RecoveryManifest({
    required this.id,
    required this.seq,
    required this.issuedAt,
    required this.origin,
    required this.key,
    this.mirrors = const <Uri>[],
    this.rendezvous = const <Uri>[],
    this.nextKey,
    this.name,
  });

  /// Restores a manifest from the map produced by [toJson].
  ///
  /// The stored form, not the wire form: it is trusted only as far as the
  /// state it is part of was.
  factory RecoveryManifest.fromJson(JsonMap json) => RecoveryManifest(
        id: '${json['id']}',
        seq: (json['seq']! as num).toInt(),
        issuedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['iat']! as num).toInt() * 1000,
          isUtc: true,
        ),
        origin: Uri.parse('${json['origin']}'),
        mirrors: <Uri>[
          for (final raw in (json['mirrors'] as List<Object?>?) ?? <Object?>[])
            Uri.parse('$raw'),
        ],
        rendezvous: <Uri>[
          for (final raw
              in (json['rendezvous'] as List<Object?>?) ?? <Object?>[])
            Uri.parse('$raw'),
        ],
        key: '${json['key']}',
        nextKey: json['next_key'] as String?,
        name: json['name'] as String?,
      );

  /// The provider's project, the same across every manifest it signs.
  final String id;

  /// Release number. Strictly grows; a smaller one is a replay.
  final int seq;

  /// When the provider signed it.
  final DateTime issuedAt;

  /// The subscription's main address: scheme, host and port, nothing else.
  final Uri origin;

  /// Spare addresses of the same panel, in the order to try them.
  final List<Uri> mirrors;

  /// Where the provider's latest manifest can be fetched when [origin] and
  /// [mirrors] are silent.
  final List<Uri> rendezvous;

  /// The key that signed this manifest: 32 bytes, base64url without padding.
  final String key;

  /// The key the provider is moving to, when it announced one.
  final String? nextKey;

  /// The provider's name, for the question put to the user.
  final String? name;

  /// Every host a client could fetch the subscription from under this
  /// manifest: [origin] first, then [mirrors].
  List<Uri> get hosts => <Uri>[origin, ...mirrors];

  /// Serialises the manifest in its wire field names.
  JsonMap toJson() => <String, Object?>{
        'v': SignedManifest.version,
        'id': id,
        'seq': seq,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'origin': origin.toString(),
        'mirrors': <String>[for (final mirror in mirrors) mirror.toString()],
        'rendezvous': <String>[
          for (final point in rendezvous) point.toString(),
        ],
        'key': key,
        if (nextKey != null) 'next_key': nextKey,
        if (name != null) 'name': name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecoveryManifest &&
          other.id == id &&
          other.seq == seq &&
          other.issuedAt == issuedAt &&
          other.origin == origin &&
          Structural.listEquals(other.mirrors, mirrors) &&
          Structural.listEquals(other.rendezvous, rendezvous) &&
          other.key == key &&
          other.nextKey == nextKey &&
          other.name == name;

  @override
  int get hashCode => Object.hash(
        id,
        seq,
        issuedAt,
        origin,
        Structural.listHash(mirrors),
        Structural.listHash(rendezvous),
        key,
        nextKey,
        name,
      );

  @override
  String toString() => 'RecoveryManifest($id #$seq, ${origin.host}, '
      '${mirrors.length} mirrors, ${rendezvous.length} meeting points)';
}

/// A manifest as it travels: `v1.<base64url JSON>.<base64url signature>`.
///
/// [parse] checks the shape and every limit of the format and nothing else.
/// The signature is checked by whoever holds an Ed25519 implementation (the
/// `SignatureVerifier` port), against [publicKey], over [signedBytes].
class SignedManifest {
  const SignedManifest._({
    required this.manifest,
    required this.signedBytes,
    required this.signature,
    required this.publicKey,
  });

  /// The only format version there is.
  static const int version = 1;

  /// Longest compact form accepted, in characters.
  static const int maxLength = 4096;

  /// Most spare addresses one manifest may name.
  static const int maxMirrors = 8;

  /// Most meeting points one manifest may name.
  static const int maxRendezvous = 4;

  /// Longest provider name shown to the user.
  static const int maxName = 64;

  /// The manifest the signature covers.
  final RecoveryManifest manifest;

  /// Exactly what was signed: the ASCII bytes of `v1.<payload>`.
  final List<int> signedBytes;

  /// The 64-byte Ed25519 signature.
  final List<int> signature;

  /// The 32-byte key the manifest names, decoded.
  final List<int> publicKey;

  /// Reads [compact], or returns `null` when it is not a well-formed
  /// manifest of this version.
  ///
  /// Strict on purpose: the string arrives from the network, from hosts the
  /// user may never have heard of, and anything it names becomes an address
  /// the client may talk to. A field out of range is a refusal, not a
  /// correction.
  static SignedManifest? parse(String compact) {
    final text = compact.trim();
    if (text.isEmpty || text.length > maxLength) {
      return null;
    }
    final parts = text.split('.');
    if (parts.length != 3 || parts[0] != 'v$version') {
      return null;
    }
    final payload = _base64Url(parts[1]);
    final signature = _base64Url(parts[2]);
    if (payload == null || signature == null || signature.length != 64) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final manifest = _manifestOf(decoded);
    if (manifest == null) {
      return null;
    }
    final publicKey = _base64Url(manifest.key);
    if (publicKey == null || publicKey.length != 32) {
      return null;
    }
    final next = manifest.nextKey;
    if (next != null && _base64Url(next)?.length != 32) {
      return null;
    }
    return SignedManifest._(
      manifest: manifest,
      signedBytes: ascii.encode('${parts[0]}.${parts[1]}'),
      signature: signature,
      publicKey: publicKey,
    );
  }

  /// The scheme, host and port of [url], as an origin the format accepts:
  /// `http(s)://host[:port]`, no user info, path, query or fragment.
  /// `null` when [url] is not one.
  static Uri? originOf(Uri url) {
    final scheme = url.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || url.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: scheme,
      host: url.host.toLowerCase(),
      port: url.hasPort ? url.port : null,
    );
  }

  static RecoveryManifest? _manifestOf(Map<String, Object?> json) {
    if (json['v'] != version) {
      return null;
    }
    final id = json['id'];
    final seq = json['seq'];
    final iat = json['iat'];
    final key = json['key'];
    if (id is! String || !_id.hasMatch(id)) {
      return null;
    }
    if (seq is! int || seq < 1 || iat is! int || iat < 0) {
      return null;
    }
    if (key is! String || key.isEmpty) {
      return null;
    }
    final origin = _origin(json['origin']);
    if (origin == null) {
      return null;
    }
    final mirrors = _list(json['mirrors'], maxMirrors, _origin);
    final rendezvous = _list(json['rendezvous'], maxRendezvous, _rendezvous);
    if (mirrors == null || rendezvous == null) {
      return null;
    }
    final nextKey = json['next_key'];
    if (nextKey != null && (nextKey is! String || nextKey.isEmpty)) {
      return null;
    }
    final name = json['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > maxName)) {
      return null;
    }
    return RecoveryManifest(
      id: id,
      seq: seq,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true),
      origin: origin,
      mirrors: mirrors,
      rendezvous: rendezvous,
      key: key,
      nextKey: nextKey as String?,
      name: (name as String?)?.trim(),
    );
  }

  /// An origin exactly as written — `http(s)://host[:port]` and nothing more.
  ///
  /// Not normalised from a longer URL: a manifest naming a path means its
  /// author expects the path to be honoured, and quietly dropping it would
  /// send the client somewhere the provider did not say.
  static Uri? _origin(Object? raw) {
    if (raw is! String || raw.length > 255) {
      return null;
    }
    final url = Uri.tryParse(raw);
    if (url == null ||
        url.userInfo.isNotEmpty ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasQuery ||
        url.hasFragment) {
      return null;
    }
    return originOf(url);
  }

  /// A meeting point: a full `https` address. Never plain `http` — what
  /// comes back is checked by its signature, but the request itself tells
  /// whoever watches the wire which provider the user is with.
  static Uri? _rendezvous(Object? raw) {
    if (raw is! String || raw.length > 512) {
      return null;
    }
    final url = Uri.tryParse(raw);
    if (url == null ||
        url.scheme.toLowerCase() != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      return null;
    }
    return url;
  }

  static List<Uri>? _list(
    Object? raw,
    int limit,
    Uri? Function(Object? item) read,
  ) {
    if (raw == null) {
      return const <Uri>[];
    }
    if (raw is! List<Object?> || raw.length > limit) {
      return null;
    }
    final out = <Uri>[];
    for (final item in raw) {
      final url = read(item);
      if (url == null) {
        return null;
      }
      if (!out.contains(url)) {
        out.add(url);
      }
    }
    return out;
  }

  static List<int>? _base64Url(String raw) {
    if (raw.isEmpty || !_base64UrlAlphabet.hasMatch(raw)) {
      return null;
    }
    final remainder = raw.length % 4;
    if (remainder == 1) {
      return null;
    }
    final padded =
        remainder == 0 ? raw : raw.padRight(raw.length + 4 - remainder, '=');
    try {
      return base64Url.decode(padded);
    } on FormatException {
      return null;
    }
  }

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static final RegExp _base64UrlAlphabet = RegExp(r'^[A-Za-z0-9_-]+$');
}
