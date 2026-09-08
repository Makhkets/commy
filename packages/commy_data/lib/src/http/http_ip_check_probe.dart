import 'dart:convert';
import 'dart:io';

import 'package:commy_data/src/http/commy_http_client.dart';
import 'package:commy_domain/commy_domain.dart';

/// [IpCheckProbe] over [CommyHttpClient] — exception E-1, the data half.
///
/// One GET, **through** the tunnel: the client it is given has to carry the
/// loopback inbound the config builder opens for exactly this purpose, because
/// on Android the app's own package is excluded from the TUN and a plain
/// socket would report the user's real address with a straight face.
///
/// The answer is read leniently, because the well-known services do not agree
/// on a shape: a JSON object with `ip` (ipinfo.io, ifconfig.co), `query`
/// (ip-api.com) or `ip_addr`, or a bare address in plain text (api.ipify.org,
/// icanhazip.com). The country comes from `country`, `country_code`,
/// `countryCode` or `country_name` when any of them is there. Anything that
/// does not contain an address is a failure, not an empty result.
class HttpIpCheckProbe implements IpCheckProbe {
  /// Creates the probe.
  const HttpIpCheckProbe({required CommyHttpClient client}) : _client = client;

  final CommyHttpClient _client;

  /// JSON keys the address may sit under, in the order they are tried.
  static const List<String> ipKeys = <String>['ip', 'query', 'ip_addr'];

  /// JSON keys the country may sit under, in the order they are tried.
  static const List<String> countryKeys = <String>[
    'country',
    'country_code',
    'countryCode',
    'country_name',
  ];

  @override
  Future<Result<IpCheckResult, CommyFailure>> probe(Uri endpoint) async {
    final response = await _client.fetchText(endpoint, throughTunnel: true);
    final failure = response.failureOrNull;
    if (failure != null) {
      return Err<IpCheckResult, CommyFailure>(failure);
    }
    final parsed = parse(response.valueOrNull?.body ?? '');
    if (parsed == null) {
      return Err<IpCheckResult, CommyFailure>(
        UnknownFailure(
          const FormatException(
            'The IP check endpoint answered with no address in it',
          ),
          StackTrace.current,
        ),
      );
    }
    return Ok<IpCheckResult, CommyFailure>(parsed);
  }

  /// Reads an address, and a country if there is one, out of [body].
  ///
  /// Returns `null` when there is no address to be found. Public so the
  /// shapes above can be pinned by tests without a client in the way.
  static IpCheckResult? parse(String body) {
    final text = body.trim();
    if (text.isEmpty) {
      return null;
    }
    if (text.startsWith('{')) {
      return _fromJson(text);
    }
    final address = InternetAddress.tryParse(text);
    return address == null ? null : IpCheckResult(ip: address.address);
  }

  static IpCheckResult? _fromJson(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final ip = _firstString(decoded, ipKeys);
    if (ip == null || InternetAddress.tryParse(ip) == null) {
      return null;
    }
    return IpCheckResult(ip: ip, country: _firstString(decoded, countryKeys));
  }

  static String? _firstString(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }
}
