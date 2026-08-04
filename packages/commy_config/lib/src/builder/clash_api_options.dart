import 'dart:math';

import 'package:commy_config/src/builder/sing_box_keys.dart';

/// Settings of the Clash API, which desktop builds use for statistics.
///
/// Two hard constraints, both from docs/09-security-privacy.md:
///
/// * **Loopback only.** The controller is a privileged surface; binding it to
///   anything but `127.0.0.1` hands the machine's network to whoever is on the
///   same LAN. The address is therefore not configurable, only the port is.
/// * **A token is mandatory.** [ClashApiOptions.generate] draws it from
///   `Random.secure`. Passing a fixed [secret] is for tests, which need the
///   generated configuration to be byte-stable.
class ClashApiOptions {
  /// Creates the options with an explicit [secret].
  const ClashApiOptions({required this.secret, this.port = defaultPort});

  /// Creates the options with a freshly drawn secret.
  factory ClashApiOptions.generate({int port = defaultPort, Random? random}) =>
      ClashApiOptions(secret: randomSecret(random: random), port: port);

  /// The only address the controller is ever bound to.
  static const String loopback = '127.0.0.1';

  /// Port used when the caller did not pick one.
  static const int defaultPort = 9090;

  /// Length of a generated secret, in bytes.
  static const int secretBytes = 16;

  /// Draws a hex secret from a cryptographic source.
  static String randomSecret({int bytes = secretBytes, Random? random}) {
    final source = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < bytes; index++) {
      buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Bearer token every request has to carry.
  final String secret;

  /// Port on [loopback] the controller listens on.
  final int port;

  /// The `external_controller` value.
  String get externalController => '$loopback:$port';

  /// Renders the block the core expects.
  Map<String, Object?> toJson() => <String, Object?>{
        SingBoxKeys.externalController: externalController,
        SingBoxKeys.secret: secret,
      };

  /// Never prints [secret].
  @override
  String toString() => 'ClashApiOptions($externalController)';
}
