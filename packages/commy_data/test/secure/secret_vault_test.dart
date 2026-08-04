import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  late InMemorySecureStore store;
  late SecretVault vault;

  setUp(() {
    store = InMemorySecureStore();
    vault = SecretVault(store: store);
  });

  group('NodeSecretParts', () {
    test('splits credentials away from transport parameters', () {
      final parts = NodeSecretParts.of(Fixtures.vlessNode().params);

      expect(parts.secret.keys, containsAll(<String>['uuid', 'sid']));
      expect(parts.public.keys, containsAll(<String>['sni', 'fp', 'flow']));
      expect(parts.public.containsKey('uuid'), isFalse);
      expect(parts.hasSecret, isTrue);
    });

    test('the public key of a Reality node is not a secret', () {
      // `pbk` is the server's *public* key. Treating it as a credential would
      // strip the one parameter the config generator cannot rebuild.
      final parts = NodeSecretParts.of(Fixtures.vlessNode().params);

      expect(parts.public.containsKey('pbk'), isTrue);
    });

    test('matching is case-insensitive', () {
      final parts = NodeSecretParts.of(const <String, Object?>{
        'UUID': 'x',
        'Password': 'y',
        'sni': 'z',
      });

      expect(parts.secret.keys.length, equals(2));
      expect(parts.public.keys, equals(<String>['sni']));
    });

    test('a node without credentials produces no secret half', () {
      final parts = NodeSecretParts.of(Fixtures.socksNode().params);

      expect(parts.hasSecret, isFalse);
    });

    test('merge puts the two halves back together', () {
      final original = Fixtures.vlessNode().params;
      final parts = NodeSecretParts.of(original);

      expect(
        NodeSecretParts.merge(parts.public, parts.secret),
        equals(original),
      );
    });
  });

  group('SecretVault', () {
    test('node params round trip', () async {
      await vault.writeNodeParams('n1', const <String, Object?>{
        'uuid': Fixtures.uuid,
      });

      final read = (await vault.readNodeParams('n1')).valueOrNull!;

      expect(read['uuid'], equals(Fixtures.uuid));
    });

    test('writing an empty map removes the entry', () async {
      await vault.writeNodeParams('n1', const <String, Object?>{'uuid': 'x'});
      await vault.writeNodeParams('n1', const <String, Object?>{});

      expect(store.snapshot.containsKey(SecretKeys.nodeParams('n1')), isFalse);
    });

    test('readAllNodeParams keys the result by node id', () async {
      await vault.writeNodeParams('n1', const <String, Object?>{'uuid': 'a'});
      await vault.writeNodeParams('n2', const <String, Object?>{'uuid': 'b'});
      await vault.writeSubscriptionUrl('s1', Fixtures.subscriptionUrl);

      final all = (await vault.readAllNodeParams()).valueOrNull!;

      expect(all.keys, containsAll(<String>['n1', 'n2']));
      expect(all.keys, hasLength(2));
    });

    test('subscription URLs round trip', () async {
      await vault.writeSubscriptionUrl('s1', Fixtures.subscriptionUrl);

      final read = (await vault.readSubscriptionUrl('s1')).valueOrNull;

      expect(read, equals(Fixtures.subscriptionUrl));
    });

    test('the core config is a secret, not a column', () async {
      const config = CoreConfig(<String, Object?>{
        'outbounds': <Object?>[
          <String, Object?>{'type': 'vless', 'uuid': Fixtures.uuid},
        ],
      });
      await vault.writeCoreConfig(config);

      final read = (await vault.readCoreConfig()).valueOrNull!;

      expect(read.encode(), contains(Fixtures.uuid));
      expect(store.snapshot[SecretKeys.coreConfig], contains(Fixtures.uuid));
    });

    test('the database key is generated once and reused', () async {
      final first = (await vault.ensureDatabaseKey()).valueOrNull!;
      final second = (await vault.ensureDatabaseKey()).valueOrNull!;

      expect(first, equals(second));
      expect(first.length, equals(SecretVault.databaseKeyBytes * 2));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(first), isTrue);
    });

    test('two vaults generate different database keys', () async {
      final other = SecretVault(store: InMemorySecureStore());

      final first = (await vault.ensureDatabaseKey()).valueOrNull!;
      final second = (await other.ensureDatabaseKey()).valueOrNull!;

      expect(first, isNot(equals(second)));
    });

    test('the clash api secret is generated once', () async {
      final first = (await vault.ensureClashApiSecret()).valueOrNull!;
      final second = (await vault.ensureClashApiSecret()).valueOrNull!;

      expect(first, equals(second));
      expect(first, isNotEmpty);
    });

    test('an unavailable keystore is reported, not swallowed', () async {
      final broken = SecretVault(
        store: InMemorySecureStore(failOnWrite: true),
      );

      expect(await broken.isAvailable(), isFalse);
      final result = await broken.writeSubscriptionUrl(
        's1',
        Fixtures.subscriptionUrl,
      );
      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test('a working keystore reports itself available and leaves no probe',
        () async {
      expect(await vault.isAvailable(), isTrue);
      expect(store.snapshot, isEmpty);
    });

    test('wipe removes everything', () async {
      await vault.writeNodeParams('n1', const <String, Object?>{'uuid': 'a'});
      await vault.ensureDatabaseKey();
      await vault.wipe();

      expect(store.snapshot, isEmpty);
    });
  });

  group('SecretKeys', () {
    test('a node key round trips through its id', () {
      final key = SecretKeys.nodeParams('node-1');

      expect(SecretKeys.nodeIdOf(key), equals('node-1'));
      expect(SecretKeys.subscriptionIdOf(key), isNull);
    });

    test('a subscription key round trips through its id', () {
      final key = SecretKeys.subscriptionUrl('sub-1');

      expect(SecretKeys.subscriptionIdOf(key), equals('sub-1'));
      expect(SecretKeys.nodeIdOf(key), isNull);
    });

    test('an unrelated key belongs to nobody', () {
      expect(SecretKeys.nodeIdOf('some.other.key'), isNull);
      expect(SecretKeys.nodeIdOf(SecretKeys.databaseKey), isNull);
    });
  });
}
