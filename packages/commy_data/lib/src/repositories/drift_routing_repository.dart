import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/database/setting_keys.dart';
import 'package:commy_data/src/mappers/routing_rule_mapper.dart';
import 'package:commy_data/src/util/combine_latest.dart';
import 'package:commy_data/src/util/json_text.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// The routing policy and the DNS policy.
///
/// The policy is stored in two pieces. The rules are a list the user edits,
/// reorders and toggles, so they get their own table; the envelope around them
/// — mode, per-app lists, LAN bypass, ad blocking — is one small object and
/// lives in the settings table. `watch` stitches the two back together.
///
/// Rule R6 applies to everything written through here: it all ends up in the
/// generated core configuration, so a change has to pass the leak checklist
/// before it ships.
class DriftRoutingRepository implements RoutingRepository {
  /// Creates the repository.
  DriftRoutingRepository({required CommyDatabase database}) : _db = database;

  /// Envelope field holding `RoutingMode.name`.
  static const String modeField = 'mode';

  /// Envelope field holding `PerAppMode.name`.
  static const String perAppModeField = 'perAppMode';

  /// Envelope field holding the per-app identifier list.
  static const String perAppPackagesField = 'perAppPackages';

  /// Envelope field holding the LAN bypass flag.
  static const String bypassLanField = 'bypassLan';

  /// Envelope field holding the ad blocking flag.
  static const String blockAdsField = 'blockAds';

  final CommyDatabase _db;

  @override
  Stream<RoutingPolicy> watch() {
    return combineLatest2<JsonMap?, List<RoutingRule>, RoutingPolicy>(
      _watchValue(SettingKeys.routingPolicy),
      _watchRules(),
      (envelope, rules) => StorageGuard.orElse(
        () => _policyOf(envelope, rules),
        () => RoutingPolicy.defaults.copyWith(rules: rules),
      ),
    );
  }

  @override
  Future<Result<RoutingPolicy, CommyFailure>> read() {
    return StorageGuard.run(() async {
      final envelope = await _readValue(SettingKeys.routingPolicy);
      final rules = await _readRules();
      return _policyOf(envelope, rules);
    });
  }

  @override
  Future<Result<void, CommyFailure>> write(RoutingPolicy policy) {
    return StorageGuard.runVoid(() async {
      await _db.transaction(() async {
        await _writeValue(SettingKeys.routingPolicy, _envelopeOf(policy));
        // The rule list is replaced wholesale: a rule the user deleted has to
        // disappear, and diffing two lists to save a few writes would be a
        // source of "the rule I removed is still routing traffic" bugs.
        await _db.delete(_db.routingRuleRows).go();
        await _db.batch((batch) {
          batch.insertAll(
            _db.routingRuleRows,
            policy.rules.map(RoutingRuleMapper.toCompanion).toList(),
          );
        });
      });
    });
  }

  @override
  Stream<DnsSettings> watchDns() {
    return _watchValue(SettingKeys.dnsSettings).map(
      (json) => json == null
          ? DnsSettings.defaults
          : StorageGuard.orElse(
              () => DnsSettings.fromJson(json),
              () => DnsSettings.defaults,
            ),
    );
  }

  @override
  Future<Result<DnsSettings, CommyFailure>> readDns() {
    return StorageGuard.run(() async {
      final json = await _readValue(SettingKeys.dnsSettings);
      return json == null ? DnsSettings.defaults : DnsSettings.fromJson(json);
    });
  }

  @override
  Future<Result<void, CommyFailure>> writeDns(DnsSettings settings) {
    return StorageGuard.runVoid(
      () => _writeValue(SettingKeys.dnsSettings, settings.toJson()),
    );
  }

  static JsonMap _envelopeOf(RoutingPolicy policy) => <String, Object?>{
        modeField: policy.mode.name,
        perAppModeField: policy.perAppMode.name,
        perAppPackagesField: policy.perAppPackages,
        bypassLanField: policy.bypassLan,
        blockAdsField: policy.blockAds,
      };

  static RoutingPolicy _policyOf(JsonMap? envelope, List<RoutingRule> rules) {
    if (envelope == null) {
      return RoutingPolicy.defaults.copyWith(rules: rules);
    }
    return RoutingPolicy(
      mode: _enumByName(
        RoutingMode.values,
        envelope[modeField],
        RoutingPolicy.defaults.mode,
      ),
      rules: rules,
      perAppMode: _enumByName(
        PerAppMode.values,
        envelope[perAppModeField],
        RoutingPolicy.defaults.perAppMode,
      ),
      perAppPackages: JsonRead.stringList(envelope, perAppPackagesField),
      bypassLan: JsonRead.boolean(
        envelope,
        bypassLanField,
        orElse: RoutingPolicy.defaults.bypassLan,
      ),
      blockAds: JsonRead.boolean(
        envelope,
        blockAdsField,
        orElse: RoutingPolicy.defaults.blockAds,
      ),
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    if (raw is! String) {
      return fallback;
    }
    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return fallback;
  }

  Stream<List<RoutingRule>> _watchRules() =>
      _rulesQuery().watch().map(_mapRules);

  Future<List<RoutingRule>> _readRules() async =>
      _mapRules(await _rulesQuery().get());

  static List<RoutingRule> _mapRules(List<RoutingRuleRow> rows) =>
      rows.map(RoutingRuleMapper.toDomain).toList();

  SimpleSelectStatement<$RoutingRuleRowsTable, RoutingRuleRow> _rulesQuery() {
    return _db.select(_db.routingRuleRows)
      ..orderBy(<OrderClauseGenerator<$RoutingRuleRowsTable>>[
        (table) => OrderingTerm(expression: table.sortIndex),
      ]);
  }

  Stream<JsonMap?> _watchValue(String key) {
    final query = _db.select(_db.settingRows)
      ..where((table) => table.key.equals(key));
    return query.watchSingleOrNull().map(
          (row) => row == null ? null : JsonText.decodeOrEmpty(row.valueJson),
        );
  }

  Future<JsonMap?> _readValue(String key) async {
    final row = await (_db.select(_db.settingRows)
          ..where((table) => table.key.equals(key)))
        .getSingleOrNull();
    return row == null ? null : JsonText.decode(row.valueJson);
  }

  Future<void> _writeValue(String key, JsonMap value) async {
    await _db.into(_db.settingRows).insertOnConflictUpdate(
          SettingRowsCompanion(
            key: Value<String>(key),
            valueJson: Value<String>(JsonText.encode(value)),
          ),
        );
  }
}
