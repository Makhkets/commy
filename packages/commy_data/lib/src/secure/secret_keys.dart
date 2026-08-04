/// The key namespace of the secure store.
///
/// One flat namespace, one prefix, no collisions with whatever else the host
/// app might have put in the keychain. Every key is derived here and nowhere
/// else, so "what exactly is in secure storage" is answerable by reading one
/// file — which is the point of rule R2 being auditable.
abstract final class SecretKeys {
  /// Prefix every key this package owns starts with.
  static const String prefix = 'commy.';

  /// Prefix of the per-node credential entries.
  static const String nodePrefix = '${prefix}node.';

  /// Prefix of the per-subscription URL entries.
  static const String subscriptionPrefix = '${prefix}sub.';

  /// Suffix of the per-node credential entries.
  static const String nodeSuffix = '.params';

  /// Suffix of the per-subscription URL entries.
  static const String subscriptionSuffix = '.url';

  /// Key of the database encryption key, when the build can use one.
  static const String databaseKey = '${prefix}db.key';

  /// Key of the generated sing-box configuration.
  ///
  /// It holds every credential in the clear, which is exactly why it is here
  /// and not in a column (docs/adr/0007-database-encryption.md).
  static const String coreConfig = '${prefix}core.config';

  /// Key of the Clash API secret used on desktop.
  static const String clashApiSecret = '${prefix}core.clash_secret';

  /// Key of the token the desktop UI authenticates to the helper with.
  static const String helperToken = '${prefix}core.helper_token';

  /// Key holding the credential params of the node [nodeId].
  static String nodeParams(String nodeId) => '$nodePrefix$nodeId$nodeSuffix';

  /// Key holding the full URL of the subscription [subscriptionId].
  static String subscriptionUrl(String subscriptionId) =>
      '$subscriptionPrefix$subscriptionId$subscriptionSuffix';

  /// The node id a [key] belongs to, or `null` when it is not a node key.
  static String? nodeIdOf(String key) => _idBetween(
        key,
        prefix: nodePrefix,
        suffix: nodeSuffix,
      );

  /// The subscription id a [key] belongs to, or `null`.
  static String? subscriptionIdOf(String key) => _idBetween(
        key,
        prefix: subscriptionPrefix,
        suffix: subscriptionSuffix,
      );

  static String? _idBetween(
    String key, {
    required String prefix,
    required String suffix,
  }) {
    if (!key.startsWith(prefix) || !key.endsWith(suffix)) {
      return null;
    }
    final id = key.substring(prefix.length, key.length - suffix.length);
    return id.isEmpty ? null : id;
  }
}
