import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/database/setting_keys.dart';
import 'package:commy_data/src/util/json_text.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Application settings and the current node selection.
///
/// Everything here is a preference, not a secret: which theme, whether the kill
/// switch is on, which node was picked last. The selected node id is an
/// identifier — the credentials it points at stay in the keystore.
///
/// A row that fails to decode falls back to the defaults rather than throwing
/// on a stream. A settings blob written by a newer build and read by an older
/// one is a real scenario (a downgrade, a restored backup), and it must not
/// leave the user staring at a crash screen.
class DriftSettingsRepository implements SettingsRepository {
  /// Creates the repository.
  DriftSettingsRepository({required CommyDatabase database}) : _db = database;

  final CommyDatabase _db;

  @override
  Stream<AppSettings> watch() {
    return _watchValue(SettingKeys.appSettings).map(
      (json) => json == null
          ? AppSettings.defaults
          : StorageGuard.orElse(
              () => AppSettings.fromJson(json),
              () => AppSettings.defaults,
            ),
    );
  }

  @override
  Future<Result<AppSettings, CommyFailure>> read() {
    return StorageGuard.run(() async {
      final json = await _readValue(SettingKeys.appSettings);
      return json == null ? AppSettings.defaults : AppSettings.fromJson(json);
    });
  }

  @override
  Future<Result<void, CommyFailure>> write(AppSettings settings) {
    return StorageGuard.runVoid(
      () => _writeValue(SettingKeys.appSettings, settings.toJson()),
    );
  }

  @override
  Future<Result<String?, CommyFailure>> readSelectedNodeId() {
    return StorageGuard.run(() async {
      final json = await _readValue(SettingKeys.selectedNodeId);
      final value = json?[SettingKeys.valueField];
      return value is String && value.isNotEmpty ? value : null;
    });
  }

  @override
  Future<Result<void, CommyFailure>> writeSelectedNodeId(String? nodeId) {
    return StorageGuard.runVoid(() async {
      if (nodeId == null || nodeId.isEmpty) {
        await (_db.delete(_db.settingRows)
              ..where((table) => table.key.equals(SettingKeys.selectedNodeId)))
            .go();
        return;
      }
      await _writeValue(
        SettingKeys.selectedNodeId,
        <String, Object?>{SettingKeys.valueField: nodeId},
      );
    });
  }

  /// Streams the node selection, for the connect button to follow.
  Stream<String?> watchSelectedNodeId() {
    return _watchValue(SettingKeys.selectedNodeId).map((json) {
      final value = json?[SettingKeys.valueField];
      return value is String && value.isNotEmpty ? value : null;
    });
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
