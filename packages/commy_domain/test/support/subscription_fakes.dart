import 'package:commy_domain/commy_domain.dart';

/// Test doubles for the two subscription use cases.
///
/// They live here rather than in one of the test files because the add path
/// and the refresh path ask the same questions of the same four ports, and a
/// second copy of a fake is a second place for its behaviour to drift.

/// A node built on one endpoint, named whatever the caller likes.
///
/// The identifier is passed in rather than derived, which is exactly what the
/// real parser does: `NodeIdFactory` hashes protocol, address, port and
/// credentials and leaves the display name out, so a panel listing one server
/// in two of its groups hands the use case two entries under one id.
ProxyNode buildNode({
  required String id,
  required String name,
  int sortIndex = 0,
}) {
  return ProxyNode(
    id: id,
    name: name,
    protocol: Protocol.vless,
    host: 'de-07.example.net',
    port: 443,
    sortIndex: sortIndex,
    params: const <String, Object?>{
      'uuid': '8f3c1e6a-9d2b-4c7f-a1e5-0b6d4a2c9f88',
      'security': 'reality',
    },
  );
}

/// A parser parked on one answer. The real one lives in commy_config, which
/// this package cannot see.
class StubLinkParser implements LinkParser {
  /// Answers every parse with [outcome].
  StubLinkParser(ParseOutcome outcome)
      : _result = Ok<ParseOutcome, CommyFailure>(outcome);

  /// Refuses every parse with [failure].
  StubLinkParser.failing(CommyFailure failure)
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

/// A fetcher that hands back a body without touching the network (R1).
class StubSubscriptionFetcher implements SubscriptionFetcher {
  /// Answers every fetch with [payload].
  StubSubscriptionFetcher([SubscriptionPayload? payload])
      : _result = Ok<SubscriptionPayload, CommyFailure>(
          payload ?? const SubscriptionPayload(body: 'vless://...'),
        );

  /// Answers every fetch with [failure].
  StubSubscriptionFetcher.failing(CommyFailure failure)
      : _result = Err<SubscriptionPayload, CommyFailure>(failure);

  final Result<SubscriptionPayload, CommyFailure> _result;

  @override
  Future<Result<SubscriptionPayload, CommyFailure>> fetch(
    Uri url, {
    required bool throughTunnel,
    String? userAgent,
  }) async =>
      _result;
}

/// An identifier source that always says the same thing.
class FixedIdGenerator implements IdGenerator {
  /// Creates a generator returning [id].
  FixedIdGenerator(this.id);

  /// What every call returns.
  final String id;

  @override
  String newId() => id;
}

/// A subscription store that keeps what it was given.
class FakeSubscriptionRepository implements SubscriptionRepository {
  final Map<String, Subscription> _rows = <String, Subscription>{};

  /// Seeds the store, for the refresh path which needs something to refresh.
  void seed(Subscription subscription) => _rows[subscription.id] = subscription;

  /// Everything the store holds.
  List<Subscription> get stored =>
      List<Subscription>.unmodifiable(_rows.values);

  @override
  Stream<List<Subscription>> watchAll() =>
      Stream<List<Subscription>>.value(stored);

  @override
  Future<Result<List<Subscription>, CommyFailure>> getAll() async =>
      Ok<List<Subscription>, CommyFailure>(stored);

  @override
  Future<Result<Subscription?, CommyFailure>> findById(String id) async =>
      Ok<Subscription?, CommyFailure>(_rows[id]);

  @override
  Future<Result<void, CommyFailure>> upsert(Subscription subscription) async {
    _rows[subscription.id] = subscription;
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> deleteById(String id) async {
    _rows.remove(id);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> setCollapsed({
    required String id,
    required bool isCollapsed,
  }) async =>
      const Ok<void, CommyFailure>(null);

  @override
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds) async =>
      const Ok<void, CommyFailure>(null);
}

/// A node store that remembers what a refresh asked it to write.
///
/// [replaceCalls] keeps every call as its own list: how many rows one refresh
/// handed the store is part of what is under test, not only what ended up
/// stored. Writing is last-wins by id, which is what the real
/// `DriftNodeRepository` does.
class RecordingNodeRepository implements NodeRepository {
  /// Every `replaceForSubscription` payload, in order.
  final List<List<ProxyNode>> replaceCalls = <List<ProxyNode>>[];

  final Map<String, ProxyNode> _rows = <String, ProxyNode>{};

  /// Set to make the write fail, for the error branch.
  CommyFailure? failure;

  /// The rows the store holds, in insertion order.
  List<ProxyNode> get stored => List<ProxyNode>.unmodifiable(_rows.values);

  @override
  Future<Result<void, CommyFailure>> replaceForSubscription({
    required String subscriptionId,
    required List<ProxyNode> nodes,
  }) async {
    final refused = failure;
    if (refused != null) {
      return Err<void, CommyFailure>(refused);
    }
    replaceCalls.add(List<ProxyNode>.unmodifiable(nodes));
    _rows.removeWhere((_, node) => node.subscriptionId == subscriptionId);
    for (final node in nodes) {
      _rows[node.id] = node;
    }
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> upsertAll(List<ProxyNode> nodes) async {
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
  Future<Result<void, CommyFailure>> updateLatency({
    required String id,
    required Duration? latency,
    required DateTime checkedAt,
  }) async =>
      const Ok<void, CommyFailure>(null);

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
