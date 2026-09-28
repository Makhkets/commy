import 'dart:convert';
import 'dart:typed_data';

import 'package:commy_domain/commy_domain.dart';

/// A "cipher" that prefixes the password. Enough to check what the use cases
/// hand it and what they do with its answers; the real sealing is tested in
/// commy_data.
class PasswordPrefixCipher implements BackupCipher {
  /// What [seal] was last given, as text.
  String? lastPlain;

  /// Set to make [seal] or [open] fail.
  CommyFailure? failure;

  @override
  Future<Result<Uint8List, CommyFailure>> seal(
    Uint8List plain,
    String password,
  ) async {
    final refused = failure;
    if (refused != null) {
      return Err(refused);
    }
    lastPlain = utf8.decode(plain);
    return Ok(
      Uint8List.fromList(<int>[...utf8.encode('$password|'), ...plain]),
    );
  }

  @override
  Future<Result<Uint8List, CommyFailure>> open(
    Uint8List sealed,
    String password,
  ) async {
    final refused = failure;
    if (refused != null) {
      return Err(refused);
    }
    final prefix = utf8.encode('$password|');
    if (sealed.length < prefix.length ||
        utf8.decode(sealed.sublist(0, prefix.length), allowMalformed: true) !=
            '$password|') {
      return const Err(BackupFailure(BackupProblem.wrongPassword));
    }
    return Ok(Uint8List.fromList(sealed.sublist(prefix.length)));
  }

  @override
  BackupProblem? inspect(Uint8List sealed) => null;

  /// What a file holding [plain] under [password] would look like.
  static Uint8List fileOf(String password, String plain) =>
      Uint8List.fromList(utf8.encode('$password|$plain'));
}

/// Settings kept in memory.
class MemorySettingsRepository implements SettingsRepository {
  /// The stored settings.
  AppSettings settings = AppSettings.defaults;

  /// The stored selection.
  String? selected;

  /// How many times [write] ran.
  int writes = 0;

  @override
  Stream<AppSettings> watch() => Stream<AppSettings>.value(settings);

  @override
  Future<Result<AppSettings, CommyFailure>> read() async => Ok(settings);

  @override
  Future<Result<void, CommyFailure>> write(AppSettings value) async {
    writes++;
    settings = value;
    return const Ok(null);
  }

  @override
  Future<Result<String?, CommyFailure>> readSelectedNodeId() async =>
      Ok(selected);

  @override
  Future<Result<void, CommyFailure>> writeSelectedNodeId(String? id) async {
    selected = id;
    return const Ok(null);
  }
}

/// Routing and DNS kept in memory.
class MemoryRoutingRepository implements RoutingRepository {
  /// The stored policy.
  RoutingPolicy policy = RoutingPolicy.defaults;

  /// The stored DNS settings.
  DnsSettings dns = DnsSettings.defaults;

  /// How many times either was written.
  int writes = 0;

  /// Set to make [read] fail.
  CommyFailure? readFailure;

  /// Set to make [write] fail.
  CommyFailure? writeFailure;

  @override
  Stream<RoutingPolicy> watch() => Stream<RoutingPolicy>.value(policy);

  @override
  Future<Result<RoutingPolicy, CommyFailure>> read() async {
    final refused = readFailure;
    return refused == null ? Ok(policy) : Err(refused);
  }

  @override
  Future<Result<void, CommyFailure>> write(RoutingPolicy value) async {
    final refused = writeFailure;
    if (refused != null) {
      return Err(refused);
    }
    writes++;
    policy = value;
    return const Ok(null);
  }

  @override
  Stream<DnsSettings> watchDns() => Stream<DnsSettings>.value(dns);

  @override
  Future<Result<DnsSettings, CommyFailure>> readDns() async => Ok(dns);

  @override
  Future<Result<void, CommyFailure>> writeDns(DnsSettings value) async {
    writes++;
    dns = value;
    return const Ok(null);
  }
}

/// Rule sets that "are on disk" by tag.
class MemoryRuleSetRepository implements RuleSetRepository {
  /// Creates the store holding [tags].
  MemoryRuleSetRepository([List<String> tags = const <String>[]])
      : _tags = tags;

  final List<String> _tags;

  List<RuleSet> get _sets => <RuleSet>[
        for (final tag in _tags)
          RuleSet(tag: tag, sizeBytes: 1, updatedAt: DateTime.utc(2026)),
      ];

  @override
  Stream<List<RuleSet>> watch() => Stream<List<RuleSet>>.value(_sets);

  @override
  Future<Result<List<RuleSet>, CommyFailure>> list() async => Ok(_sets);

  @override
  Future<Result<String, CommyFailure>> directory() async => const Ok('/tmp');

  @override
  Future<Result<RuleSet, CommyFailure>> download({
    required String tag,
    required Uri from,
  }) async =>
      throw UnimplementedError('a restore never downloads');

  @override
  Future<Result<void, CommyFailure>> delete(String tag) async => const Ok(null);
}

/// A library store that records the one call a restore makes, and hands an
/// export whatever it was seeded with.
class RecordingLibraryStore implements LibraryStore {
  /// What [readLibrary] returns.
  ({
    List<Subscription> subscriptions,
    List<NodeGroup> groups,
    List<ProxyNode> nodes,
  }) contents = (
    subscriptions: const <Subscription>[],
    groups: const <NodeGroup>[],
    nodes: const <ProxyNode>[],
  );

  /// Set to make [readLibrary] fail, as an unreadable keystore does.
  CommyFailure? readFailure;

  @override
  Future<
      Result<
          ({
            List<Subscription> subscriptions,
            List<NodeGroup> groups,
            List<ProxyNode> nodes,
          }),
          CommyFailure>> readLibrary() async {
    final refused = readFailure;
    return refused == null ? Ok(contents) : Err(refused);
  }

  /// The subscriptions of the last replace.
  List<Subscription>? subscriptions;

  /// The groups of the last replace.
  List<NodeGroup>? groups;

  /// The servers of the last replace.
  List<ProxyNode>? nodes;

  /// Set to make the replace fail.
  CommyFailure? failure;

  @override
  Future<Result<void, CommyFailure>> replaceLibrary({
    required List<Subscription> subscriptions,
    required List<NodeGroup> groups,
    required List<ProxyNode> nodes,
  }) async {
    final refused = failure;
    if (refused != null) {
      return Err(refused);
    }
    this.subscriptions = subscriptions;
    this.groups = groups;
    this.nodes = nodes;
    return const Ok(null);
  }
}
