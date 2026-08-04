import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';

/// Strips the credentials out of a generated configuration before it leaves
/// the device.
///
/// docs/06-data-model.md makes exporting the generated configuration a
/// supported way to debug, "**с редакцией кредов** по умолчанию". The document
/// holds every secret in the clear, and these files get pasted into GitHub
/// issues — so redaction is the default and the raw form takes an explicit
/// argument.
abstract final class ConfigRedactor {
  /// Keys whose value is a credential, in the spelling the core uses.
  ///
  /// A superset of `ProxyNode.secretParamKeys`: the configuration writes
  /// `private_key` and `short_id` where a link writes `privateKey` and `sid`,
  /// and it adds the Clash API `secret`, which no link has.
  static const Set<String> secretKeys = <String>{
    'auth',
    'auth_str',
    'password',
    'plugin_opts',
    'pre_shared_key',
    'private_key',
    'psk',
    'secret',
    'short_id',
    'token',
    'username',
    'uuid',
  };

  /// Keys that name the user's own server.
  static const Set<String> serverKeys = <String>{'server', 'address'};

  /// Renders [config] as pretty JSON with every credential blanked.
  ///
  /// [hideServers] additionally replaces server addresses, which is what an
  /// export attached to a public issue needs.
  static String export(
    CoreConfig config, {
    bool redact = true,
    bool hideServers = false,
  }) {
    final document = redact
        ? redactValue(config.document, hideServers: hideServers)
        : config.document;
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Walks [value], blanking anything credential-like.
  static Object? redactValue(Object? value, {bool hideServers = false}) {
    if (value is Map<String, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        result[entry.key] = _redactEntry(entry, hideServers: hideServers);
      }
      return result;
    }
    if (value is List<Object?>) {
      return <Object?>[
        for (final item in value) redactValue(item, hideServers: hideServers),
      ];
    }
    return value;
  }

  static Object? _redactEntry(
    MapEntry<String, Object?> entry, {
    required bool hideServers,
  }) {
    final key = entry.key.toLowerCase();
    if (secretKeys.contains(key)) {
      return _blank(entry.value);
    }
    if (hideServers && serverKeys.contains(key)) {
      return _replaceServer(entry.value);
    }
    return redactValue(entry.value, hideServers: hideServers);
  }

  static Object? _blank(Object? value) {
    if (value is List<Object?>) {
      return <Object?>[for (final _ in value) Redact.placeholder];
    }
    if (value == null) {
      return null;
    }
    return Redact.placeholder;
  }

  static Object? _replaceServer(Object? value) {
    if (value is List<Object?>) {
      return <Object?>[for (final _ in value) Redact.serverPlaceholder];
    }
    if (value == null) {
      return null;
    }
    return Redact.serverPlaceholder;
  }
}
