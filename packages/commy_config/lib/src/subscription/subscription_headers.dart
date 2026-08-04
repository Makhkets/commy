import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_domain/commy_domain.dart';

/// The metadata a panel puts in the response headers of a subscription.
///
/// Marzban, Remnawave, x-ui and the rest all speak the same handful of
/// headers (docs/06-data-model.md):
///
/// ```text
/// subscription-userinfo: upload=0; download=0; total=0; expire=0
/// profile-title: base64:0JzQvtC5INC/0YDQvtGE0LjQu9GM
/// profile-update-interval: 24
/// profile-web-page-url: https://panel.example.com/
/// ```
///
/// Nothing here is required. A header that is missing means the block is not
/// shown, never that a number is invented.
class SubscriptionHeaders {
  const SubscriptionHeaders._(this._values);

  /// Reads headers out of a response map.
  ///
  /// Values may be a single string or a list of them, which is what every
  /// HTTP client hands back for repeated headers. Names are matched
  /// case-insensitively because no two panels agree on the casing.
  factory SubscriptionHeaders.from(Map<String, Object?> raw) {
    final values = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = entry.value;
      if (key.isEmpty || value == null) {
        continue;
      }
      if (value is List<Object?>) {
        if (value.isEmpty) {
          continue;
        }
        values.putIfAbsent(key, () => '${value.first}'.trim());
      } else {
        values.putIfAbsent(key, () => '$value'.trim());
      }
    }
    return SubscriptionHeaders._(values);
  }

  /// Headers with nothing in them.
  static const SubscriptionHeaders empty =
      SubscriptionHeaders._(<String, String>{});

  /// Header holding the quota and expiry block.
  static const String userInfoHeader = 'subscription-userinfo';

  /// Header holding the display name of the profile.
  static const String titleHeader = 'profile-title';

  /// Header holding the refresh interval, in hours.
  static const String updateIntervalHeader = 'profile-update-interval';

  /// Header holding the provider's web page.
  static const String webPageHeader = 'profile-web-page-url';

  /// Headers that may hold a support contact, in order of preference.
  static const List<String> supportHeaders = <String>[
    'support-url',
    'profile-support-url',
  ];

  /// Headers that may hold a broadcast message, in order of preference.
  static const List<String> announceHeaders = <String>[
    'announce',
    'announce-url',
    'profile-announce',
  ];

  /// Marker some panels put in front of a base64 encoded header value.
  static const String base64Prefix = 'base64:';

  /// Epoch seconds above which a timestamp is read as milliseconds.
  static const int millisecondThreshold = 100000000000;

  final Map<String, String> _values;

  /// The raw value of [name], or `null`.
  String? value(String name) {
    final found = _values[name.trim().toLowerCase()];
    return found == null || found.isEmpty ? null : found;
  }

  /// The first non-empty value among [names].
  String? valueOf(List<String> names) {
    for (final name in names) {
      final found = value(name);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Quota and expiry, or `null` when the panel said nothing.
  SubscriptionUserInfo? get userInfo {
    final raw = value(userInfoHeader);
    if (raw == null) {
      return null;
    }
    final fields = <String, int>{};
    for (final part in raw.split(';')) {
      final split = part.indexOf('=');
      if (split <= 0) {
        continue;
      }
      final key = part.substring(0, split).trim().toLowerCase();
      final parsed = int.tryParse(part.substring(split + 1).trim());
      if (parsed != null) {
        fields[key] = parsed;
      }
    }
    if (fields.isEmpty) {
      return null;
    }
    return SubscriptionUserInfo(
      upload: fields['upload'],
      download: fields['download'],
      total: fields['total'],
      expire: _expiry(fields['expire']),
    );
  }

  /// Display name of the profile, already decoded.
  String? get profileTitle => decodeHeaderText(value(titleHeader));

  /// Refresh interval in hours, or `null`.
  int? get updateIntervalHours {
    final raw = value(updateIntervalHeader);
    final parsed = raw == null ? null : int.tryParse(raw.trim());
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  /// The provider's web page, or `null`.
  Uri? get profileWebPageUrl => _uri(value(webPageHeader));

  /// The provider's support contact, or `null`.
  Uri? get supportUrl => _uri(valueOf(supportHeaders));

  /// A broadcast message from the panel, already decoded.
  String? get announcement => decodeHeaderText(valueOf(announceHeaders));

  /// Wraps [body] together with everything read here.
  SubscriptionPayload toPayload(String body) => SubscriptionPayload(
        body: body,
        userInfo: userInfo,
        profileTitle: profileTitle,
        profileWebPageUrl: profileWebPageUrl,
        supportUrl: supportUrl,
        updateIntervalHours: updateIntervalHours,
      );

  /// Decodes a header value that may be base64, percent-encoded or plain.
  ///
  /// A `base64:` prefix is always honoured. Without it a value is only
  /// decoded when it is unambiguously base64 — correctly padded, no spaces,
  /// and decoding to text rather than to bytes. Anything else is a title that
  /// merely happens to be spelled in base64-legal characters, and mangling it
  /// would be worse than leaving it alone.
  static String? decodeHeaderText(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final unescaped = Percent.decode(raw).trim();
    if (unescaped.isEmpty) {
      return null;
    }
    if (unescaped.toLowerCase().startsWith(base64Prefix)) {
      final payload = unescaped.substring(base64Prefix.length).trim();
      return LenientBase64.decodeToString(payload) ?? payload;
    }
    if (unescaped.contains(' ') || unescaped.length % 4 != 0) {
      return unescaped;
    }
    return LenientBase64.decodeToString(unescaped) ?? unescaped;
  }

  static DateTime? _expiry(int? seconds) {
    if (seconds == null || seconds <= 0) {
      return null;
    }
    final milliseconds =
        seconds > millisecondThreshold ? seconds : seconds * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static Uri? _uri(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
    return parsed;
  }

  @override
  String toString() => 'SubscriptionHeaders(${_values.length} headers)';
}
