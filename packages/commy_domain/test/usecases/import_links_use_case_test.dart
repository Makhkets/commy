import 'dart:async';

import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// The identifier of a node deliberately leaves the display name out: panels
/// rename servers between refreshes, and an identifier that moved on a rename
/// would throw away the measured latency every time. Two entries that differ
/// only by name are therefore the same server, and the store holds one row for
/// both.
///
/// That collapse is correct. What is not is reporting two of them: the import
/// panel is shown once, there is no import history, and an over-count is never
/// corrected afterwards.
ProxyNode buildNode({
  required String id,
  required String name,
  int sortIndex = 0,
}) {
  return ProxyNode(
    id: id,
    name: name,
    protocol: Protocol.vless,
    host: 'nl-03.example.net',
    port: 443,
    sortIndex: sortIndex,
    params: const <String, Object?>{
      'uuid': '11111111-2222-3333-4444-555555555555',
      'security': 'reality',
    },
  );
}

ImportLinksUseCase _importer(_StubParser parser, _FakeNodeRepository nodes) =>
    ImportLinksUseCase(parser: parser, nodes: nodes);

void main() {
  group('ImportLinksUseCase', () {
    test('reports the servers the store gained, not the lines parsed',
        () async {
      // The bug this guards: a user pastes the same server twice under two
      // names, the panel says two and the library holds one.
      final parser = _StubParser(
        ParseOutcome(
          nodes: <ProxyNode>[
            buildNode(id: 'same', name: 'Amsterdam 03'),
            buildNode(id: 'same', name: 'Amsterdam 03 (backup)', sortIndex: 1),
          ],
        ),
      );
      final nodes = _FakeNodeRepository();

      final result = await _importer(parser, nodes)('two links, one server');

      expect(result.valueOrNull?.nodes, hasLength(1));
      expect(nodes.stored, hasLength(1));
      // The store is written once, too: the second write would only overwrite
      // the row the first one made, secrets and all.
      expect(nodes.upsertCalls.single, hasLength(1));
    });

    test('the entry that survives is the one an upsert would have left',
        () async {
      // Importing "A then B" in one paste has to land where importing A and
      // then B separately lands, which is the later entry.
      final parser = _StubParser(
        ParseOutcome(
          nodes: <ProxyNode>[
            buildNode(id: 'same', name: 'Amsterdam 03'),
            buildNode(id: 'same', name: 'Amsterdam 03 (backup)', sortIndex: 1),
          ],
        ),
      );
      final nodes = _FakeNodeRepository();

      await _importer(parser, nodes)('two links, one server');

      expect(nodes.stored.single.name, 'Amsterdam 03 (backup)');
      expect(nodes.stored.single.sortIndex, 1);
    });

    test('a first import of distinct servers reports every one of them',
        () async {
      final parser = _StubParser(
        ParseOutcome(
          nodes: <ProxyNode>[
            buildNode(id: 'nl', name: 'Amsterdam 03'),
            buildNode(id: 'pl', name: 'Warsaw 10', sortIndex: 1),
            buildNode(id: 'no', name: 'Oslo 01', sortIndex: 2),
          ],
        ),
      );
      final nodes = _FakeNodeRepository();

      final result = await _importer(parser, nodes)('three links');

      expect(result.valueOrNull?.nodes, hasLength(3));
      expect(nodes.stored, hasLength(3));
      expect(
        result.valueOrNull?.nodes.map((node) => node.name),
        <String>['Amsterdam 03', 'Warsaw 10', 'Oslo 01'],
      );
    });

    test('collapsing duplicates leaves the skipped lines alone', () async {
      const skipped = ImportFailure(
        rawLine: 'a shopping list, copied by accident',
        reason: 'not a link',
      );
      final parser = _StubParser(
        ParseOutcome(
          nodes: <ProxyNode>[
            buildNode(id: 'same', name: 'Amsterdam 03'),
            buildNode(id: 'same', name: 'Amsterdam 03 (backup)', sortIndex: 1),
          ],
          failures: const <ImportFailure>[skipped],
        ),
      );
      final nodes = _FakeNodeRepository();

      final result = await _importer(parser, nodes)('one server and junk');

      expect(result.valueOrNull?.failures, <ImportFailure>[skipped]);
    });

    test('puts the stored nodes in the group it was given', () async {
      final parser = _StubParser(
        ParseOutcome(
          nodes: <ProxyNode>[
            buildNode(id: 'same', name: 'Amsterdam 03'),
            buildNode(id: 'same', name: 'Amsterdam 03 (backup)', sortIndex: 1),
          ],
        ),
      );
      final nodes = _FakeNodeRepository();

      await _importer(parser, nodes)('two links', groupId: 'g1');

      expect(nodes.stored.single.groupId, 'g1');
    });

    test('a write the store refused is not reported as an import', () async {
      final parser = _StubParser(
        ParseOutcome(
          nodes: <ProxyNode>[buildNode(id: 'nl', name: 'Amsterdam 03')],
        ),
      );
      final nodes = _FakeNodeRepository()
        ..failure = const StorageFailure('database is locked');

      final result = await _importer(parser, nodes)('one link');

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(result.valueOrNull, isNull);
    });

    test('nothing parsed is an empty success, and nothing is written',
        () async {
      final parser = _StubParser(ParseOutcome.empty);
      final nodes = _FakeNodeRepository();

      final result = await _importer(parser, nodes)('nothing parseable');

      expect(result.valueOrNull?.hasNodes, isFalse);
      expect(nodes.upsertCalls, isEmpty);
    });

    test('a parser that refused the input at all fails the import', () async {
      final parser = _StubParser.failing(
        const SubscriptionMalformedFailure('not a subscription'),
      );
      final nodes = _FakeNodeRepository();

      final result = await _importer(parser, nodes)('junk');

      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
      expect(nodes.upsertCalls, isEmpty);
    });
  });
}

/// A parser parked on one answer. The real one lives in commy_config, which
/// this package cannot see.
class _StubParser implements LinkParser {
  _StubParser(ParseOutcome outcome)
      : _result = Ok<ParseOutcome, CommyFailure>(outcome);

  _StubParser.failing(CommyFailure failure)
      : _result = Err<ParseOutcome, CommyFailure>(failure);

  final Result<ParseOutcome, CommyFailure> _result;

  @override
  bool canParse(String input) => true;

  @override
  Result<ParseOutcome, CommyFailure> parse(String input) => _result;

  @override
  Result<String, CommyFailure> toLink(ProxyNode node) =>
      const Err<String, CommyFailure>(ConfigInvalidFailure('no link form'));
}

/// A store that remembers what it was asked to write.
///
/// [upsertCalls] keeps every call as its own list: how many rows one import
/// wrote is part of what is under test, not only what ended up stored.
class _FakeNodeRepository implements NodeRepository {
  final List<List<ProxyNode>> upsertCalls = <List<ProxyNode>>[];
  final Map<String, ProxyNode> _rows = <String, ProxyNode>{};

  /// Set to make the write fail, for the error branch.
  CommyFailure? failure;

  /// The rows the store holds, in insertion order.
  List<ProxyNode> get stored => List<ProxyNode>.unmodifiable(_rows.values);

  @override
  Future<Result<void, CommyFailure>> upsertAll(List<ProxyNode> nodes) async {
    final refused = failure;
    if (refused != null) {
      return Err<void, CommyFailure>(refused);
    }
    upsertCalls.add(List<ProxyNode>.unmodifiable(nodes));
    for (final node in nodes) {
      _rows[node.id] = node;
    }
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Stream<List<ProxyNode>> watchAll() => Stream<List<ProxyNode>>.value(stored);

  @override
  Future<Result<List<ProxyNode>, CommyFailure>> getAll() async =>
      Ok<List<ProxyNode>, CommyFailure>(stored);

  @override
  Future<Result<ProxyNode?, CommyFailure>> findById(String id) async =>
      Ok<ProxyNode?, CommyFailure>(_rows[id]);

  @override
  Future<Result<List<ProxyNode>, CommyFailure>> findBySubscription(
    String subscriptionId,
  ) async {
    return Ok<List<ProxyNode>, CommyFailure>(
      <ProxyNode>[
        for (final node in stored)
          if (node.subscriptionId == subscriptionId) node,
      ],
    );
  }

  @override
  Future<Result<void, CommyFailure>> deleteById(String id) async {
    _rows.remove(id);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> deleteBySubscription(
    String subscriptionId,
  ) async {
    _rows.removeWhere((_, node) => node.subscriptionId == subscriptionId);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> replaceForSubscription({
    required String subscriptionId,
    required List<ProxyNode> nodes,
  }) async {
    await deleteBySubscription(subscriptionId);
    return upsertAll(nodes);
  }

  @override
  Future<Result<void, CommyFailure>> updateLatency({
    required String id,
    required Duration? latency,
    required DateTime checkedAt,
  }) async {
    final node = _rows[id];
    if (node != null) {
      _rows[id] = node.copyWith(latency: latency, lastCheckedAt: checkedAt);
    }
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds) async =>
      const Ok<void, CommyFailure>(null);

  @override
  Stream<List<NodeGroup>> watchGroups() =>
      Stream<List<NodeGroup>>.value(const <NodeGroup>[]);

  @override
  Future<Result<void, CommyFailure>> upsertGroup(NodeGroup group) async =>
      const Ok<void, CommyFailure>(null);

  @override
  Future<Result<void, CommyFailure>> deleteGroup(String id) async =>
      const Ok<void, CommyFailure>(null);
}
