import 'package:drift/drift.dart';

/// Key-value settings, one JSON object per key.
///
/// A column per toggle would mean a migration per toggle, and this is a client
/// whose settings screen grows every release. The keys are enumerated in
/// `SettingKeys`; nothing writes a key that is not listed there.
///
/// Nothing sensitive goes in here — the selected node id is an identifier, not
/// a credential.
@DataClassName('SettingRow')
class SettingRows extends Table {
  /// One of the constants in `SettingKeys`.
  TextColumn get key => text()();

  /// The value, as an encoded JSON object.
  TextColumn get valueJson => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};

  @override
  String get tableName => 'settings';
}
