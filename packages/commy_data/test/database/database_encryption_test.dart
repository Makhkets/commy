import 'package:commy_data/commy_data.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the honesty of the encryption story.
///
/// docs/adr/0007-database-encryption.md accepts that 1.0 ships with a plain
/// metadata database, on the condition that the app *says so*. These tests
/// check the two halves of that condition: the status is reported, and a key is
/// never handed out for an encryption that is not going to happen.
void main() {
  group('DatabaseEncryption', () {
    test('the cipher probe answers without throwing', () {
      // Plain SQLite returns no rows for an unknown pragma; SQLCipher and
      // SQLite3MultipleCiphers return a version. Either is a valid answer —
      // what must never happen is an exception on the startup path.
      expect(DatabaseEncryption.probeCipherSupport, returnsNormally);
    });

    test('the plan reports a status and matches it with a key', () async {
      final vault = SecretVault(store: InMemorySecureStore());
      final encryption = DatabaseEncryption(vault: vault);

      final plan = await encryption.plan();

      if (plan.isEncrypted) {
        expect(plan.keyHex, isNotNull);
        expect(
          plan.keyHex!.length,
          equals(SecretVault.databaseKeyBytes * 2),
        );
      } else {
        // No key is produced for an encryption that will not happen: a key
        // sitting unused in the keystore reads like protection that exists.
        expect(plan.keyHex, isNull);
        expect(
          plan.status,
          anyOf(
            DatabaseEncryptionStatus.unavailable,
            DatabaseEncryptionStatus.keyUnavailable,
          ),
        );
      }
    });

    test('a plan never prints its key', () async {
      final vault = SecretVault(store: InMemorySecureStore());
      final plan = await DatabaseEncryption(vault: vault).plan();
      final key = plan.keyHex;

      if (key != null) {
        expect(plan.toString(), isNot(contains(key)));
      }
      expect(plan.toString(), contains(plan.status.name));
    });

    test('a keystore that cannot store a key reports keyUnavailable', () async {
      final vault = SecretVault(
        store: InMemorySecureStore(failOnWrite: true),
      );
      final encryption = DatabaseEncryption(vault: vault);

      expect(await encryption.obtainKey(), isNull);

      final plan = await encryption.plan();
      expect(plan.isEncrypted, isFalse);
      expect(plan.keyHex, isNull);
    });
  });

  group('OpenedDatabase', () {
    test('anything but encrypted is a degraded state the UI must show',
        () async {
      final database = CommyDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      for (final status in DatabaseEncryptionStatus.values) {
        final opened = OpenedDatabase(database: database, encryption: status);

        expect(
          opened.isDegraded,
          equals(status != DatabaseEncryptionStatus.encrypted),
        );
      }
    });
  });
}
