import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

void main() {
  late TestStack stack;
  late DriftSubscriptionRepository repository;

  setUp(() {
    stack = TestStack.create();
    repository = stack.subscriptions;
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftSubscriptionRepository', () {
    test('a saved subscription comes back with its URL', () async {
      final subscription = Fixtures.subscription();
      await repository.upsert(subscription);

      final loaded = (await repository.findById(subscription.id)).valueOrNull!;

      expect(loaded.url, equals(Fixtures.subscriptionUrl));
      expect(loaded.name, equals('Example panel'));
      expect(loaded.autoUpdate, isTrue);
      expect(loaded.updateIntervalHours, equals(12));
      expect(loaded.userInfo?.total, equals(107374182400));
      expect(loaded.userInfo?.expire, equals(DateTime.utc(2027)));
    });

    test('the URL lives in the keystore, not in the row', () async {
      final subscription = Fixtures.subscription();
      await repository.upsert(subscription);

      final key = SecretKeys.subscriptionUrl(subscription.id);

      expect(
        stack.store.snapshot[key],
        equals(Fixtures.subscriptionUrl.toString()),
      );
      expect(
        (await stack.dumpAllValues()).join('\n'),
        isNot(contains(Fixtures.subscriptionUrl.path)),
      );
    });

    test('a lost secret degrades to the redacted URL, not to a crash',
        () async {
      final subscription = Fixtures.subscription();
      await repository.upsert(subscription);
      await stack.store.delete(SecretKeys.subscriptionUrl(subscription.id));

      final loaded = (await repository.findById(subscription.id)).valueOrNull!;

      expect(loaded.name, equals('Example panel'));
      expect(loaded.url, equals(Redact.uriValue(Fixtures.subscriptionUrl)));
      expect(loaded.url.toString(), isNot(contains('9f8e7d6c')));
    });

    test('watchAll emits in display order', () async {
      await repository.upsert(Fixtures.subscription(id: 'b', sortIndex: 1));
      await repository.upsert(Fixtures.subscription());
      await repository.upsert(Fixtures.subscription(id: 'a'));

      final emitted = await repository.watchAll().first;
      final ids = emitted.map((item) => item.id).toList();

      expect(ids.first, isNot(equals('b')));
      expect(ids.last, equals('b'));
    });

    test('setCollapsed folds the group', () async {
      final subscription = Fixtures.subscription();
      await repository.upsert(subscription);
      await repository.setCollapsed(id: subscription.id, isCollapsed: true);

      final loaded = (await repository.findById(subscription.id)).valueOrNull!;

      expect(loaded.isCollapsed, isTrue);
    });

    test('reorder rewrites the display order', () async {
      await repository.upsert(Fixtures.subscription(id: 'first'));
      await repository.upsert(Fixtures.subscription(id: 'second'));
      await repository.reorder(<String>['second', 'first']);

      final all = (await repository.getAll()).valueOrNull!;

      expect(all.first.id, equals('second'));
    });

    test('deleting removes the row, the URL and the node credentials',
        () async {
      final subscription = Fixtures.subscription();
      await repository.upsert(subscription);
      await stack.nodes.upsertAll(<ProxyNode>[
        Fixtures.vlessNode(subscriptionId: subscription.id),
      ]);

      await repository.deleteById(subscription.id);

      expect((await repository.getAll()).valueOrNull, isEmpty);
      expect((await stack.nodes.getAll()).valueOrNull, isEmpty);
      expect(
        stack.store.snapshot.keys.where(
          (key) => key.startsWith(SecretKeys.prefix),
        ),
        isEmpty,
      );
    });

    test('a keystore that refuses to write fails the save', () async {
      final broken = TestStack.create(
        store: InMemorySecureStore(failOnWrite: true),
      );
      addTearDown(broken.dispose);

      final result = await broken.subscriptions.upsert(Fixtures.subscription());

      expect(result.isErr, isTrue);
      expect((await broken.subscriptions.getAll()).valueOrNull, isEmpty);
    });
  });
}
