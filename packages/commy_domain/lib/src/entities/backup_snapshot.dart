import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/dns_settings.dart';
import 'package:commy_domain/src/entities/node_group.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/routing.dart';
import 'package:commy_domain/src/entities/subscription.dart';

/// Everything a user would have to set up again on a new phone, in one value.
///
/// What goes in is the user's own work: subscriptions with their URLs, every
/// server with its credentials, routing, DNS, the app's settings, the selected
/// server and which rule sets were in use. What stays out, and why
/// (docs/adr/0017-encrypted-backup.md):
///
/// - the installation id sent as `x-hwid` — it names *this* installation
///   (ADR-0009); copied to a second phone it would make two devices one to
///   the panel;
/// - traffic history, logs, import failures — records of what happened
///   here, not choices anyone made;
/// - rule-set files — megabytes that the rule-set source serves again, and
///   downloading them stays the user's decision (exception E-2);
/// - measured latencies — from another network, they would only mislead
///   "sort by latency".
///
/// The value is plain data. Turning it into bytes nobody else can read is
/// the `BackupCipher`'s job; this class only knows the JSON inside.
class BackupSnapshot {
  /// Creates a snapshot.
  const BackupSnapshot({
    required this.createdAt,
    required this.appVersion,
    required this.platform,
    this.subscriptions = const <Subscription>[],
    this.groups = const <NodeGroup>[],
    this.nodes = const <ProxyNode>[],
    this.routing,
    this.dns,
    this.settings,
    this.selectedNodeId,
    this.ruleSets = const <String>[],
    this.skipped = 0,
  });

  /// Reads the JSON [toJson] wrote.
  ///
  /// Lenient where leniency keeps the user's data and strict where it would
  /// invent some. A server this version does not understand — a protocol
  /// added later — is left out and counted in [skipped] rather than failing
  /// the whole restore over one row. A section that does not parse (settings
  /// with a value from a newer Commy) comes back null, which means "keep what
  /// this phone has". A payload that is not a snapshot at all throws
  /// [FormatException]. Ask [schemaOf] first: a payload from a newer
  /// [schema] is a different answer for the user than a broken one.
  ///
  /// References are made to hold: a server whose subscription or group is not
  /// in the file becomes a server of its own, and a selection that names a
  /// server not in the file is dropped. The database would refuse the first
  /// and the tunnel would fail on the second.
  factory BackupSnapshot.fromJson(JsonMap json) {
    final version = schemaOf(json);
    if (version == null || version > schema) {
      throw FormatException('not a backup payload this version reads', version);
    }
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    if (createdAt == null) {
      throw const FormatException('no creation time');
    }
    var skipped = 0;

    final subscriptions = <Subscription>[];
    final subscriptionIds = <String>{};
    for (final raw in _list(json, 'subscriptions')) {
      final subscription = _tryParse(raw, Subscription.fromJson);
      if (subscription == null || !subscriptionIds.add(subscription.id)) {
        skipped++;
        continue;
      }
      subscriptions.add(subscription);
    }

    final groups = <NodeGroup>[];
    final groupIds = <String>{};
    for (final raw in _list(json, 'groups')) {
      final group = _tryParse(raw, NodeGroup.fromJson);
      if (group == null || !groupIds.add(group.id)) {
        skipped++;
        continue;
      }
      groups.add(group);
    }

    final nodes = <ProxyNode>[];
    final nodeIds = <String>{};
    for (final raw in _list(json, 'nodes')) {
      final node = _tryParse(raw, ProxyNode.fromJson);
      if (node == null || !nodeIds.add(node.id)) {
        skipped++;
        continue;
      }
      final subscriptionId = node.subscriptionId;
      final groupId = node.groupId;
      nodes.add(
        node.copyWith(
          subscriptionId: subscriptionId != null &&
                  !subscriptionIds.contains(subscriptionId)
              ? null
              : subscriptionId,
          groupId:
              groupId != null && !groupIds.contains(groupId) ? null : groupId,
        ),
      );
    }

    final routing = _routingOf(json['routing']);
    skipped += routing.skipped;
    final selected = json['selectedNodeId'];
    return BackupSnapshot(
      createdAt: createdAt,
      appVersion: '${json['appVersion'] ?? ''}',
      platform: '${json['platform'] ?? ''}',
      subscriptions: subscriptions,
      groups: groups,
      nodes: nodes,
      routing: routing.policy,
      dns: _tryParse(json['dns'], DnsSettings.fromJson),
      settings: _tryParse(json['settings'], AppSettings.fromJson),
      selectedNodeId:
          selected is String && nodeIds.contains(selected) ? selected : null,
      ruleSets: <String>[
        for (final tag in json['ruleSets'] is List
            ? json['ruleSets']! as List<Object?>
            : const <Object?>[])
          if (tag is String && tag.isNotEmpty) tag,
      ],
      skipped: skipped,
    );
  }

  /// The payload schema [json] declares, or null when it is not a backup
  /// payload at all.
  static int? schemaOf(JsonMap json) {
    final version = json['schema'];
    return json['format'] == format && version is int ? version : null;
  }

  /// What the payload calls itself, so a stray JSON file is not taken for one.
  static const String format = 'commy-backup';

  /// The payload layout this version writes, and the newest it reads.
  ///
  /// Separate from the file container's version: the container says how the
  /// bytes are sealed, this says what the JSON inside means.
  static const int schema = 1;

  /// When the backup was made, in UTC.
  final DateTime createdAt;

  /// The Commy version that made it, for the user and for bug reports.
  final String appVersion;

  /// The platform it was made on (`android`, `ios`, …). Per-app routing names
  /// packages on Android and executables on a desktop, so it matters.
  final String platform;

  /// Every subscription, with its URL — an access token (rule R2).
  final List<Subscription> subscriptions;

  /// Manual groups. Nothing creates them yet; the schema is ready for them.
  final List<NodeGroup> groups;

  /// Every server, subscribed and manual, with its credentials.
  final List<ProxyNode> nodes;

  /// Routing, with its rules in order; null when it did not parse.
  final RoutingPolicy? routing;

  /// DNS; null when it did not parse.
  final DnsSettings? dns;

  /// The app's settings; null when they did not parse.
  final AppSettings? settings;

  /// The server that was selected, if it is among [nodes].
  final String? selectedNodeId;

  /// Tags of the rule sets that were on disk. The files are not in the
  /// backup: after a restore they are downloaded again, on the user's tap.
  final List<String> ruleSets;

  /// Entries left out while reading: a newer protocol, a duplicate, a row
  /// that did not parse.
  final int skipped;

  /// Servers the user added by hand rather than through a subscription.
  int get manualNodeCount =>
      nodes.where((node) => node.subscriptionId == null).length;

  /// The JSON that goes inside the sealed file.
  ///
  /// Times in UTC, so a backup made in Moscow restores to the same moment in
  /// Berlin. Latency and when it was measured are left out (see the class
  /// comment).
  JsonMap toJson() => <String, Object?>{
        'format': format,
        'schema': schema,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'platform': platform,
        'subscriptions': <JsonMap>[
          for (final subscription in subscriptions)
            <String, Object?>{
              ...subscription.toJson(),
              'lastUpdatedAt':
                  subscription.lastUpdatedAt?.toUtc().toIso8601String(),
            },
        ],
        'groups': <JsonMap>[
          for (final group in groups)
            <String, Object?>{
              ...group.toJson(),
              'createdAt': group.createdAt?.toUtc().toIso8601String(),
            },
        ],
        'nodes': <JsonMap>[
          for (final node in nodes)
            <String, Object?>{...node.toJson()}
              ..remove('latencyMicros')
              ..remove('lastCheckedAt'),
        ],
        'routing': routing?.toJson(),
        'dns': dns?.toJson(),
        'settings': settings?.toJson(),
        'selectedNodeId': selectedNodeId,
        'ruleSets': ruleSets,
      };

  /// The routing section, one rule at a time: a rule with an action this
  /// version does not know costs that rule, not the user's whole rule list.
  static ({RoutingPolicy? policy, int skipped}) _routingOf(Object? raw) {
    if (raw is! Map) {
      return (policy: null, skipped: 0);
    }
    final json = raw.cast<String, Object?>();
    final envelope = _tryParse(
      <String, Object?>{...json}..remove('rules'),
      RoutingPolicy.fromJson,
    );
    if (envelope == null) {
      return (policy: null, skipped: 0);
    }
    var skipped = 0;
    final rules = <RoutingRule>[];
    for (final item in _list(json, 'rules')) {
      final rule = _tryParse(item, RoutingRule.fromJson);
      if (rule == null) {
        skipped++;
        continue;
      }
      rules.add(rule);
    }
    return (policy: envelope.copyWith(rules: rules), skipped: skipped);
  }

  static List<Object?> _list(JsonMap json, String key) {
    final value = json[key];
    return value is List ? value.cast<Object?>() : const <Object?>[];
  }

  static T? _tryParse<T>(Object? raw, T Function(JsonMap json) parse) {
    if (raw is! Map) {
      return null;
    }
    try {
      return parse(raw.cast<String, Object?>());
      // A row from a newer Commy throws whatever its parser throws: a
      // TypeError for a missing field, an ArgumentError for an enum value this
      // version has never heard of. Each costs one row, not the restore.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}
