/// In-memory stand-ins for the four repositories the screens read.
///
/// They exist so a widget test can render the home screen without opening
/// SQLite or touching a keystore. They are deliberately thin: every method
/// either does the obvious thing or returns a failure the test asked for, and
/// none of them models storage behaviour the real repositories have.
library;

import 'dart:async';

import 'package:commy_domain/commy_domain.dart';

/// A node store backed by a list.
class FakeNodeRepository implements NodeRepository {
  /// Creates the store, optionally pre-filled.
  FakeNodeRepository([List<ProxyNode> initial = const <ProxyNode>[]]) {
    _nodes.addAll(initial);
  }

  final List<ProxyNode> _nodes = <ProxyNode>[];
  final List<NodeGroup> _groups = <NodeGroup>[];
  final StreamController<List<ProxyNode>> _nodeChanges =
      StreamController<List<ProxyNode>>.broadcast();
  final StreamController<List<NodeGroup>> _groupChanges =
      StreamController<List<NodeGroup>>.broadcast();

  /// Set to make every write fail, for the error-state tests.
  CommyFailure? failure;

  /// Everything currently stored.
  List<ProxyNode> get nodes => List<ProxyNode>.unmodifiable(_nodes);

  /// Releases the broadcast controllers.
  Future<void> dispose() async {
    await _nodeChanges.close();
    await _groupChanges.close();
  }

  @override
  Stream<List<ProxyNode>> watchAll() => _replay(_nodeChanges, () => nodes);

  @override
  Stream<List<NodeGroup>> watchGroups() => _replay(
        _groupChanges,
        () => List<NodeGroup>.unmodifiable(_groups),
      );

  @override
  Future<Result<List<ProxyNode>, CommyFailure>> getAll() async =>
      _wrap(() => nodes);

  @override
  Future<Result<ProxyNode?, CommyFailure>> findById(String id) async {
    return _wrap(() {
      for (final node in _nodes) {
        if (node.id == id) {
          return node;
        }
      }
      return null;
    });
  }

  @override
  Future<Result<List<ProxyNode>, CommyFailure>> findBySubscription(
    String subscriptionId,
  ) async {
    return _wrap(
      () => <ProxyNode>[
        for (final node in _nodes)
          if (node.subscriptionId == subscriptionId) node,
      ],
    );
  }

  @override
  Future<Result<void, CommyFailure>> upsertAll(List<ProxyNode> nodes) async {
    return _wrapVoid(() {
      for (final node in nodes) {
        _nodes
          ..removeWhere((existing) => existing.id == node.id)
          ..add(node);
      }
      _publishNodes();
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteById(String id) async {
    return _wrapVoid(() {
      _nodes.removeWhere((node) => node.id == id);
      _publishNodes();
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteBySubscription(
    String subscriptionId,
  ) async {
    return _wrapVoid(() {
      _nodes.removeWhere((node) => node.subscriptionId == subscriptionId);
      _publishNodes();
    });
  }

  @override
  Future<Result<void, CommyFailure>> replaceForSubscription({
    required String subscriptionId,
    required List<ProxyNode> nodes,
  }) async {
    return _wrapVoid(() {
      _nodes
        ..removeWhere((node) => node.subscriptionId == subscriptionId)
        ..addAll(nodes);
      _publishNodes();
    });
  }

  @override
  Future<Result<void, CommyFailure>> updateLatency({
    required String id,
    required Duration? latency,
    required DateTime checkedAt,
  }) async {
    return _wrapVoid(() {
      for (var index = 0; index < _nodes.length; index++) {
        if (_nodes[index].id == id) {
          _nodes[index] = _nodes[index].copyWith(
            latency: latency,
            lastCheckedAt: checkedAt,
          );
        }
      }
      _publishNodes();
    });
  }

  @override
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds) async {
    return _wrapVoid(_publishNodes);
  }

  @override
  Future<Result<void, CommyFailure>> upsertGroup(NodeGroup group) async {
    return _wrapVoid(() {
      _groups
        ..removeWhere((existing) => existing.id == group.id)
        ..add(group);
      _groupChanges.add(List<NodeGroup>.unmodifiable(_groups));
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteGroup(String id) async {
    return _wrapVoid(() {
      _groups.removeWhere((group) => group.id == id);
      _groupChanges.add(List<NodeGroup>.unmodifiable(_groups));
    });
  }

  void _publishNodes() => _nodeChanges.add(nodes);

  Result<T, CommyFailure> _wrap<T>(T Function() read) {
    final error = failure;
    return error == null
        ? Ok<T, CommyFailure>(read())
        : Err<T, CommyFailure>(error);
  }

  Result<void, CommyFailure> _wrapVoid(void Function() write) {
    final error = failure;
    if (error != null) {
      return Err<void, CommyFailure>(error);
    }
    write();
    return const Ok<void, CommyFailure>(null);
  }
}

/// A subscription store backed by a list.
class FakeSubscriptionRepository implements SubscriptionRepository {
  /// Creates the store, optionally pre-filled.
  FakeSubscriptionRepository([
    List<Subscription> initial = const <Subscription>[],
  ]) {
    _items.addAll(initial);
  }

  final List<Subscription> _items = <Subscription>[];
  final StreamController<List<Subscription>> _changes =
      StreamController<List<Subscription>>.broadcast();

  /// Everything currently stored.
  List<Subscription> get items => List<Subscription>.unmodifiable(_items);

  /// Releases the broadcast controller.
  Future<void> dispose() => _changes.close();

  @override
  Stream<List<Subscription>> watchAll() => _replay(_changes, () => items);

  @override
  Future<Result<List<Subscription>, CommyFailure>> getAll() async =>
      Ok<List<Subscription>, CommyFailure>(items);

  @override
  Future<Result<Subscription?, CommyFailure>> findById(String id) async {
    for (final item in _items) {
      if (item.id == id) {
        return Ok<Subscription?, CommyFailure>(item);
      }
    }
    return const Ok<Subscription?, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> upsert(Subscription subscription) async {
    _items
      ..removeWhere((existing) => existing.id == subscription.id)
      ..add(subscription);
    _changes.add(items);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> deleteById(String id) async {
    _items.removeWhere((item) => item.id == id);
    _changes.add(items);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> setCollapsed({
    required String id,
    required bool isCollapsed,
  }) async {
    for (var index = 0; index < _items.length; index++) {
      if (_items[index].id == id) {
        _items[index] = _items[index].copyWith(isCollapsed: isCollapsed);
      }
    }
    _changes.add(items);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds) async {
    _changes.add(items);
    return const Ok<void, CommyFailure>(null);
  }
}

/// Settings kept in a field.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates the store.
  FakeSettingsRepository({AppSettings settings = AppSettings.defaults})
      : _settings = settings;

  AppSettings _settings;
  String? _selectedNodeId;
  final StreamController<AppSettings> _changes =
      StreamController<AppSettings>.broadcast();

  /// The id last written by the connect or switch flow.
  String? get selectedNodeId => _selectedNodeId;

  /// Releases the broadcast controller.
  Future<void> dispose() => _changes.close();

  @override
  Stream<AppSettings> watch() => _replay(_changes, () => _settings);

  @override
  Future<Result<AppSettings, CommyFailure>> read() async =>
      Ok<AppSettings, CommyFailure>(_settings);

  @override
  Future<Result<void, CommyFailure>> write(AppSettings settings) async {
    _settings = settings;
    _changes.add(settings);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Future<Result<String?, CommyFailure>> readSelectedNodeId() async =>
      Ok<String?, CommyFailure>(_selectedNodeId);

  @override
  Future<Result<void, CommyFailure>> writeSelectedNodeId(
    String? nodeId,
  ) async {
    _selectedNodeId = nodeId;
    return const Ok<void, CommyFailure>(null);
  }
}

/// Routing policy and DNS kept in fields.
class FakeRoutingRepository implements RoutingRepository {
  /// Creates the store.
  FakeRoutingRepository({
    RoutingPolicy policy = RoutingPolicy.defaults,
    DnsSettings dns = DnsSettings.defaults,
  })  : _policy = policy,
        _dns = dns;

  RoutingPolicy _policy;
  DnsSettings _dns;
  final StreamController<RoutingPolicy> _policyChanges =
      StreamController<RoutingPolicy>.broadcast();
  final StreamController<DnsSettings> _dnsChanges =
      StreamController<DnsSettings>.broadcast();

  /// Releases the broadcast controllers.
  Future<void> dispose() async {
    await _policyChanges.close();
    await _dnsChanges.close();
  }

  @override
  Stream<RoutingPolicy> watch() => _replay(_policyChanges, () => _policy);

  @override
  Future<Result<RoutingPolicy, CommyFailure>> read() async =>
      Ok<RoutingPolicy, CommyFailure>(_policy);

  @override
  Future<Result<void, CommyFailure>> write(RoutingPolicy policy) async {
    _policy = policy;
    _policyChanges.add(policy);
    return const Ok<void, CommyFailure>(null);
  }

  @override
  Stream<DnsSettings> watchDns() => _replay(_dnsChanges, () => _dns);

  @override
  Future<Result<DnsSettings, CommyFailure>> readDns() async =>
      Ok<DnsSettings, CommyFailure>(_dns);

  @override
  Future<Result<void, CommyFailure>> writeDns(DnsSettings settings) async {
    _dns = settings;
    _dnsChanges.add(settings);
    return const Ok<void, CommyFailure>(null);
  }
}

/// A clipboard that holds whatever the test put in it.
class FakeClipboard implements ClipboardPort {
  /// Creates the clipboard with [text] already in it.
  FakeClipboard([this.text]);

  /// What a read returns.
  String? text;

  @override
  Future<Result<String?, CommyFailure>> read() async =>
      Ok<String?, CommyFailure>(text);

  @override
  Future<Result<void, CommyFailure>> write(String value) async {
    text = value;
    return const Ok<void, CommyFailure>(null);
  }
}

/// A stream that replays the current value to every new listener.
///
/// The real Drift streams do this, and a screen that only ever sees the
/// *next* write would sit on its skeleton forever.
Stream<T> _replay<T>(StreamController<T> controller, T Function() current) {
  return Stream<T>.multi((listener) {
    listener.add(current());
    final subscription = controller.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = subscription.cancel;
  });
}
