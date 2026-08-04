import 'package:commy_data/src/database/tables/node_group_rows.dart';
import 'package:commy_data/src/database/tables/subscription_rows.dart';
import 'package:drift/drift.dart';

/// One proxy server, minus its credentials.
///
/// Rule R2 and docs/adr/0007-database-encryption.md draw the line here:
///
/// * [publicParamsJson] holds the transport half of `ProxyNode.params` —
///   `sni`, `fp`, `alpn`, `path`, `serviceName` and friends;
/// * everything listed in `ProxyNode.secretParamKeys` — `uuid`, `password`,
///   `private_key`, `short_id` — is stripped out before the row is written and
///   lives in the secure store under the key named by [secretRef];
/// * [host] and [port] stay in the clear on purpose. They are visible to any
///   observer the moment the tunnel comes up, so hiding them here would buy
///   nothing and cost every list render a keystore round trip.
@DataClassName('NodeRow')
class NodeRows extends Table {
  /// Stable identifier. Survives a subscription refresh where possible.
  TextColumn get id => text()();

  /// Display name, as the panel wrote it.
  TextColumn get name => text()();

  /// `Protocol.name`, matching what `ProxyNode.toJson` writes.
  TextColumn get protocol => text()();

  /// Server hostname or address.
  TextColumn get host => text()();

  /// Server port.
  IntColumn get port => integer()();

  /// Subscription this node came from, or `null` when added by hand.
  TextColumn get subscriptionId => text()
      .nullable()
      .references(SubscriptionRows, #id, onDelete: KeyAction.cascade)();

  /// Manual group this node belongs to, or `null`.
  TextColumn get groupId => text()
      .nullable()
      .references(NodeGroupRows, #id, onDelete: KeyAction.cascade)();

  /// ISO 3166-1 alpha-2 country code, when it could be derived.
  TextColumn get countryCode => text().nullable()();

  /// Last measured round trip in microseconds, or `null`.
  IntColumn get latencyMicros => integer().nullable()();

  /// When the latency was measured.
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();

  /// Position inside its subscription or group.
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// Non-credential protocol parameters, as a JSON object.
  TextColumn get publicParamsJson => text().withDefault(const Constant('{}'))();

  /// Secure-store key holding the credential parameters, or `null`.
  ///
  /// `null` means this node genuinely has no secrets — a bare `socks://` used
  /// for local debugging, for instance — not that they were lost.
  TextColumn get secretRef => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  String get tableName => 'nodes';
}
