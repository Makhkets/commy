/// The complete list of keys the `settings` table may hold.
///
/// A key-value table is only maintainable while the keys are enumerated in one
/// place. Adding one here is cheap; discovering an undocumented key in a user's
/// database three releases later is not.
abstract final class SettingKeys {
  /// `AppSettings.toJson`.
  static const String appSettings = 'app_settings';

  /// The parts of `RoutingPolicy` that are not the rule list.
  static const String routingPolicy = 'routing_policy';

  /// `DnsSettings.toJson`.
  static const String dnsSettings = 'dns_settings';

  /// The node the user last picked, as `{"value": "<id>"}`.
  static const String selectedNodeId = 'selected_node_id';

  /// Field the single-value keys wrap their payload in.
  static const String valueField = 'value';

  /// Every key this build knows about.
  static const List<String> all = <String>[
    appSettings,
    routingPolicy,
    dnsSettings,
    selectedNodeId,
  ];
}
