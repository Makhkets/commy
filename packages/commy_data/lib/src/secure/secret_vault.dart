import 'dart:math';

import 'package:commy_data/src/secure/secret_keys.dart';
import 'package:commy_data/src/secure/secure_store.dart';
import 'package:commy_data/src/util/json_text.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';

/// Everything rule R2 puts out of reach of the plain database.
///
/// One typed door onto `SecureStore`, so that "which secrets does Commy hold"
/// is a list of methods rather than a scattering of string keys:
///
/// * node credentials — uuid, password, private key, Reality short id;
/// * subscription URLs, whole, because the access token is inside them;
/// * the generated sing-box configuration, which inlines all of the above;
/// * the Clash API secret and the desktop helper token;
/// * the database encryption key, for the day the build can use one.
///
/// Every method returns a `Result`; nothing here throws upward.
class SecretVault {
  /// Creates a vault on top of [store].
  ///
  /// [random] is only injected by tests that need a deterministic key.
  SecretVault({required SecureStore store, Random? random})
      : _store = store,
        _random = random ?? Random.secure();

  /// Length of the database encryption key, in bytes.
  static const int databaseKeyBytes = 32;

  static const int _byteCeiling = 256;

  final SecureStore _store;
  final Random _random;

  // ── Node credentials ──────────────────────────────────────────────────────

  /// Stores the credential half of a node's parameters.
  ///
  /// An empty [params] deletes the entry instead of writing `{}`: a node with
  /// nothing to hide should not own a keystore slot.
  Future<Result<void, CommyFailure>> writeNodeParams(
    String nodeId,
    Map<String, Object?> params,
  ) =>
      StorageGuard.runVoid(() async {
        final key = SecretKeys.nodeParams(nodeId);
        if (params.isEmpty) {
          await _store.delete(key);
          return;
        }
        await _store.write(key, JsonText.encode(params));
      });

  /// Reads the credential half of a node's parameters.
  Future<Result<Map<String, Object?>, CommyFailure>> readNodeParams(
    String nodeId,
  ) =>
      StorageGuard.run(() async {
        final raw = await _store.read(SecretKeys.nodeParams(nodeId));
        return raw == null ? JsonText.emptyObject : JsonText.decode(raw);
      });

  /// Reads the credentials of every node in one pass, keyed by node id.
  ///
  /// `watchAll` hydrates a whole list on every emission; doing that with one
  /// platform call instead of N is the difference between a smooth list and a
  /// visible stutter on Android.
  Future<Result<Map<String, Map<String, Object?>>, CommyFailure>>
      readAllNodeParams() => StorageGuard.run(() async {
            final all = await _store.readAll();
            final result = <String, Map<String, Object?>>{};
            for (final entry in all.entries) {
              final nodeId = SecretKeys.nodeIdOf(entry.key);
              if (nodeId == null) {
                continue;
              }
              result[nodeId] = JsonText.decodeOrEmpty(entry.value);
            }
            return result;
          });

  /// Removes the credentials of [nodeId].
  Future<Result<void, CommyFailure>> deleteNodeParams(String nodeId) =>
      StorageGuard.runVoid(
        () => _store.delete(SecretKeys.nodeParams(nodeId)),
      );

  /// Removes the credentials of several nodes at once.
  Future<Result<void, CommyFailure>> deleteNodeParamsAll(
    Iterable<String> nodeIds,
  ) =>
      StorageGuard.runVoid(() async {
        for (final nodeId in nodeIds) {
          await _store.delete(SecretKeys.nodeParams(nodeId));
        }
      });

  // ── Subscription URLs ─────────────────────────────────────────────────────

  /// Stores the full URL of a subscription.
  Future<Result<void, CommyFailure>> writeSubscriptionUrl(
    String subscriptionId,
    Uri url,
  ) =>
      StorageGuard.runVoid(
        () => _store.write(
          SecretKeys.subscriptionUrl(subscriptionId),
          url.toString(),
        ),
      );

  /// Reads the full URL of a subscription, or `null` when it is gone.
  Future<Result<Uri?, CommyFailure>> readSubscriptionUrl(
    String subscriptionId,
  ) =>
      StorageGuard.run(() async {
        final raw =
            await _store.read(SecretKeys.subscriptionUrl(subscriptionId));
        return raw == null ? null : Uri.parse(raw);
      });

  /// Reads every subscription URL in one pass, keyed by subscription id.
  Future<Result<Map<String, Uri>, CommyFailure>> readAllSubscriptionUrls() =>
      StorageGuard.run(() async {
        final all = await _store.readAll();
        final result = <String, Uri>{};
        for (final entry in all.entries) {
          final id = SecretKeys.subscriptionIdOf(entry.key);
          if (id == null) {
            continue;
          }
          final parsed = Uri.tryParse(entry.value);
          if (parsed != null) {
            result[id] = parsed;
          }
        }
        return result;
      });

  /// Removes the URL of a subscription.
  Future<Result<void, CommyFailure>> deleteSubscriptionUrl(
    String subscriptionId,
  ) =>
      StorageGuard.runVoid(
        () => _store.delete(SecretKeys.subscriptionUrl(subscriptionId)),
      );

  // ── Core configuration and control-channel secrets ────────────────────────

  /// Caches the configuration last handed to the core.
  ///
  /// It contains every credential in the clear — that observation is what sent
  /// it here rather than into a column (docs/06-data-model.md, "Шифрование").
  Future<Result<void, CommyFailure>> writeCoreConfig(CoreConfig config) =>
      StorageGuard.runVoid(
        () => _store.write(SecretKeys.coreConfig, config.encode()),
      );

  /// Reads back the cached core configuration.
  Future<Result<CoreConfig?, CommyFailure>> readCoreConfig() =>
      StorageGuard.run(() async {
        final raw = await _store.read(SecretKeys.coreConfig);
        return raw == null ? null : CoreConfig(JsonText.decode(raw));
      });

  /// Drops the cached core configuration.
  Future<Result<void, CommyFailure>> deleteCoreConfig() =>
      StorageGuard.runVoid(() => _store.delete(SecretKeys.coreConfig));

  /// Reads the Clash API secret, creating one on first use.
  ///
  /// Desktop only: the control channel is a loopback HTTP server and an
  /// unauthenticated one would let any local process steer the tunnel
  /// (docs/09-security-privacy.md, "Управляющий канал на десктопе").
  Future<Result<String, CommyFailure>> ensureClashApiSecret() =>
      _ensureRandomHex(SecretKeys.clashApiSecret, databaseKeyBytes);

  /// Reads the desktop helper token, creating one on first use.
  Future<Result<String, CommyFailure>> ensureHelperToken() =>
      _ensureRandomHex(SecretKeys.helperToken, databaseKeyBytes);

  // ── Database key ──────────────────────────────────────────────────────────

  /// Reads the database encryption key, generating it on first run.
  ///
  /// 32 bytes out of `Random.secure`, hex encoded because that is the form
  /// `PRAGMA key = "x'...'"` wants. Whether the key gets used at all depends on
  /// the SQLite build — see `DatabaseEncryption`.
  Future<Result<String, CommyFailure>> ensureDatabaseKey() =>
      _ensureRandomHex(SecretKeys.databaseKey, databaseKeyBytes);

  /// Whether a database key has already been generated.
  Future<Result<bool, CommyFailure>> hasDatabaseKey() =>
      StorageGuard.run(() => _store.contains(SecretKeys.databaseKey));

  // ── Health ────────────────────────────────────────────────────────────────

  /// Probes whether the platform actually has a working secure store.
  ///
  /// On Linux without libsecret there is none, and the app must say so out
  /// loud rather than quietly fall back to a file
  /// (docs/09-security-privacy.md, "Известная слабость"). Writes a value,
  /// reads it back and removes it.
  Future<bool> isAvailable() async {
    const probeKey = '${SecretKeys.prefix}probe';
    try {
      await _store.write(probeKey, 'ok');
      final readBack = await _store.read(probeKey);
      await _store.delete(probeKey);
      return readBack == 'ok';
    } on Object catch (_) {
      return false;
    }
  }

  /// Wipes every secret this app owns. Used by "erase all data".
  Future<Result<void, CommyFailure>> wipe() =>
      StorageGuard.runVoid(_store.deleteAll);

  Future<Result<String, CommyFailure>> _ensureRandomHex(
    String key,
    int byteCount,
  ) =>
      StorageGuard.run(() async {
        final existing = await _store.read(key);
        if (existing != null && existing.isNotEmpty) {
          return existing;
        }
        final generated = _randomHex(byteCount);
        await _store.write(key, generated);
        return generated;
      });

  String _randomHex(int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      final byte = _random.nextInt(_byteCeiling);
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
