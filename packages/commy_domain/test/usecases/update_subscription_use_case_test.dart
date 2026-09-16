import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/subscription_fakes.dart';

/// A refresh reports the same number a first import does, and for the same
/// reason: the entries a panel lists are not the rows the store keeps. One
/// endpoint in two of the panel's groups is one server, because a node's
/// identity leaves the display name out, and the refresh toast is shown once.
void main() {
  group('UpdateSubscriptionUseCase', () {
    test('reports the servers the store holds, not the entries listed',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.valueOrNull?.importedCount, 1);
      expect(nodes.stored, hasLength(1));
      expect(nodes.replaceCalls.single, hasLength(1));
    });

    test('the entry that survives is the one a write would have left',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      await useCase(subscriptionId: 'sub-1');

      expect(nodes.stored.single.name, 'Games · Frankfurt 07');
    });

    test('a refresh with no repeats reports every server', () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'de', name: 'Frankfurt 07'),
              buildNode(id: 'nl', name: 'Amsterdam 03', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.valueOrNull?.importedCount, 2);
      expect(nodes.replaceCalls.single, hasLength(2));
    });

    test('the refreshed nodes stay with the subscription they came from',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(nodes.stored.single.subscriptionId, 'sub-1');
      expect(result.valueOrNull?.outcome.nodes.single.subscriptionId, 'sub-1');
    });

    test('collapsing repeats leaves the skipped entries alone', () async {
      const skipped = ImportFailure(
        rawLine: 'ss://truncated-line',
        reason: 'not a link',
      );
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
            failures: const <ImportFailure>[skipped],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.valueOrNull?.skippedCount, 1);
      expect(result.valueOrNull?.outcome.failures, <ImportFailure>[skipped]);
    });

    test('an unknown subscription is refused before anything is written',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'no-such-id');

      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
      expect(nodes.replaceCalls, isEmpty);
    });
  });
}

UpdateSubscriptionUseCase _useCase({
  required StubLinkParser parser,
  required RecordingNodeRepository nodes,
}) {
  final subscriptions = FakeSubscriptionRepository()
    ..seed(
      Subscription(
        id: 'sub-1',
        name: 'Example panel',
        url: Uri.parse('https://panel.example.com/sub/token?f=v2ray'),
        autoUpdate: true,
      ),
    );
  return UpdateSubscriptionUseCase(
    fetcher: StubSubscriptionFetcher(),
    parser: parser,
    subscriptions: subscriptions,
    nodes: nodes,
  );
}
