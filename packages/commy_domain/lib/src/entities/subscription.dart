import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/core/redaction.dart';
import 'package:commy_domain/src/core/sentinel.dart';

/// Quota and expiry a panel reported in the `subscription-userinfo` header.
///
/// Every field is optional: panels report what they feel like, and inventing
/// the rest is worse than showing nothing (docs/06-data-model.md).
class SubscriptionUserInfo {
  /// Creates the quota block.
  const SubscriptionUserInfo({
    this.upload,
    this.download,
    this.total,
    this.expire,
  });

  /// Restores the quota block from the map produced by [toJson].
  factory SubscriptionUserInfo.fromJson(JsonMap json) => SubscriptionUserInfo(
        upload: JsonRead.integerOrNull(json, 'upload'),
        download: JsonRead.integerOrNull(json, 'download'),
        total: JsonRead.integerOrNull(json, 'total'),
        expire: JsonRead.dateTimeOrNull(json, 'expire'),
      );

  /// How many days before expiry the UI starts warning.
  static const int expiringThresholdDays = 3;

  /// Which share of the quota counts as "nearly out".
  static const double nearQuotaRatio = 0.9;

  /// Bytes uploaded, as counted by the panel.
  final int? upload;

  /// Bytes downloaded, as counted by the panel.
  final int? download;

  /// Total quota in bytes. `null` or non-positive means unlimited.
  final int? total;

  /// When the subscription runs out.
  final DateTime? expire;

  /// Whether the panel reported a finite quota.
  bool get hasQuota => total != null && total! > 0;

  /// Bytes spent so far, or `null` when the panel reported neither figure.
  int? get usedBytes {
    if (upload == null && download == null) {
      return null;
    }
    return (upload ?? 0) + (download ?? 0);
  }

  /// Bytes left, or `null` when the quota is unlimited or unknown.
  ///
  /// Never negative: panels do overshoot their own numbers.
  int? get remainingBytes {
    final quota = total;
    final used = usedBytes;
    if (quota == null || quota <= 0 || used == null) {
      return null;
    }
    final left = quota - used;
    return left < 0 ? 0 : left;
  }

  /// Share of the quota already spent, in `0..1`, or `null` when unknown.
  double? get ratio {
    final quota = total;
    final used = usedBytes;
    if (quota == null || quota <= 0 || used == null) {
      return null;
    }
    final value = used / quota;
    if (value < 0) {
      return 0;
    }
    return value > 1 ? 1 : value;
  }

  /// Whole days left at [now], negative once expired, `null` when unknown.
  int? daysLeftAt(DateTime now) {
    final deadline = expire;
    if (deadline == null) {
      return null;
    }
    return deadline.difference(now).inDays;
  }

  /// Whole days left counted from the current wall clock.
  int? get daysLeft => daysLeftAt(DateTime.now());

  /// Whether the subscription has already run out at [now].
  bool isExpiredAt(DateTime now) {
    final deadline = expire;
    return deadline != null && !now.isBefore(deadline);
  }

  /// Whether the subscription has already run out.
  bool get isExpired => isExpiredAt(DateTime.now());

  /// Whether expiry is close enough at [now] to warn about it.
  bool isExpiringAt(DateTime now) {
    final days = daysLeftAt(now);
    return days != null && days <= expiringThresholdDays;
  }

  /// Whether expiry is close enough to warn about it.
  bool get isExpiring => isExpiringAt(DateTime.now());

  /// Whether the quota is nearly gone.
  bool get isNearQuota {
    final spent = ratio;
    return spent != null && spent >= nearQuotaRatio;
  }

  /// Returns a copy with the given fields replaced.
  SubscriptionUserInfo copyWith({
    Object? upload = Sentinel.unset,
    Object? download = Sentinel.unset,
    Object? total = Sentinel.unset,
    Object? expire = Sentinel.unset,
  }) {
    return SubscriptionUserInfo(
      upload:
          identical(upload, Sentinel.unset) ? this.upload : upload as int?,
      download: identical(download, Sentinel.unset)
          ? this.download
          : download as int?,
      total: identical(total, Sentinel.unset) ? this.total : total as int?,
      expire: identical(expire, Sentinel.unset)
          ? this.expire
          : expire as DateTime?,
    );
  }

  /// Serialises the quota block.
  JsonMap toJson() => <String, Object?>{
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire?.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionUserInfo &&
          other.upload == upload &&
          other.download == download &&
          other.total == total &&
          other.expire == expire;

  @override
  int get hashCode => Object.hash(upload, download, total, expire);

  @override
  String toString() =>
      'SubscriptionUserInfo(up: $upload, down: $download, '
      'total: $total, expire: $expire)';
}

/// A remote source of nodes, plus everything the panel told us about itself.
///
/// [url] carries an access token, so it is a secret (rule R2): the data layer
/// keeps it in secure storage and only a reference to it in the database.
/// Nothing may print it raw — use [redacted] or [Redact.uri].
class Subscription {
  /// Creates a subscription.
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.userInfo,
    this.profileTitle,
    this.announcement,
    this.profileWebPageUrl,
    this.supportUrl,
    this.updateIntervalHours,
    this.userAgentOverride,
    this.autoUpdate = false,
    this.lastUpdatedAt,
    this.sortIndex = 0,
    this.isCollapsed = false,
  });

  /// Restores a subscription from the map produced by [toJson].
  factory Subscription.fromJson(JsonMap json) => Subscription(
        id: JsonRead.string(json, 'id'),
        name: JsonRead.string(json, 'name'),
        url: JsonRead.uri(json, 'url'),
        userInfo: json['userInfo'] == null
            ? null
            : SubscriptionUserInfo.fromJson(
                JsonRead.objectOrEmpty(json, 'userInfo'),
              ),
        profileTitle: JsonRead.stringOrNull(json, 'profileTitle'),
        announcement: JsonRead.stringOrNull(json, 'announcement'),
        profileWebPageUrl: JsonRead.uriOrNull(json, 'profileWebPageUrl'),
        supportUrl: JsonRead.uriOrNull(json, 'supportUrl'),
        updateIntervalHours: JsonRead.integerOrNull(
          json,
          'updateIntervalHours',
        ),
        userAgentOverride: JsonRead.stringOrNull(json, 'userAgentOverride'),
        autoUpdate: JsonRead.boolean(json, 'autoUpdate', orElse: false),
        lastUpdatedAt: JsonRead.dateTimeOrNull(json, 'lastUpdatedAt'),
        sortIndex: JsonRead.integerOr(json, 'sortIndex', orElse: 0),
        isCollapsed: JsonRead.boolean(json, 'isCollapsed', orElse: false),
      );

  /// Stable identifier.
  final String id;

  /// Name the user gave it, falling back to [profileTitle] on import.
  final String name;

  /// Where to fetch it from. Secret: holds the access token.
  final Uri url;

  /// Quota and expiry, when the panel reported them.
  final SubscriptionUserInfo? userInfo;

  /// `profile-title` header, already decoded from its base64 form.
  final String? profileTitle;

  /// Free-text line the panel admin wrote for their users.
  ///
  /// Comes from the `announce` header (Remnawave and Marzban both send it) and
  /// renders as-is under the quota bar — `id: Makhkets · связь в телеграм
  /// @tmaac` in the mock. Rewriting or truncating it is not our call: it is the
  /// admin talking to their own users, and it is often where the support
  /// contact actually lives.
  final String? announcement;

  /// `profile-web-page-url` header: the panel's own page.
  final Uri? profileWebPageUrl;

  /// Support contact the panel advertises, when it does.
  final Uri? supportUrl;

  /// `profile-update-interval` header, in hours.
  final int? updateIntervalHours;

  /// User-Agent to send instead of the honest `Commy/<version>`.
  ///
  /// Panels serve different formats per client. We do not masquerade by
  /// default; this exists because some panels leave no other option.
  final String? userAgentOverride;

  /// Whether the app refreshes this subscription on a timer.
  final bool autoUpdate;

  /// When it was last fetched successfully.
  final DateTime? lastUpdatedAt;

  /// Position in the list on the main screen.
  final int sortIndex;

  /// Whether its node group is folded away in the UI.
  final bool isCollapsed;

  /// Effective refresh interval, honouring the panel's own suggestion.
  Duration get updateInterval =>
      Duration(hours: updateIntervalHours ?? defaultUpdateIntervalHours);

  /// Fallback refresh interval when the panel suggests none.
  static const int defaultUpdateIntervalHours = 24;

  /// Whether an automatic refresh is due at [now].
  bool isRefreshDueAt(DateTime now) {
    if (!autoUpdate) {
      return false;
    }
    final last = lastUpdatedAt;
    if (last == null) {
      return true;
    }
    return !now.isBefore(last.add(updateInterval));
  }

  /// A copy safe to print: [url] loses its path and query.
  ///
  /// The result is not a working subscription any more. That is the point.
  Subscription redacted() => copyWith(url: Redact.uriValue(url));

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` explicitly to a nullable field clears it.
  Subscription copyWith({
    String? id,
    String? name,
    Uri? url,
    Object? userInfo = Sentinel.unset,
    Object? profileTitle = Sentinel.unset,
    Object? announcement = Sentinel.unset,
    Object? profileWebPageUrl = Sentinel.unset,
    Object? supportUrl = Sentinel.unset,
    Object? updateIntervalHours = Sentinel.unset,
    Object? userAgentOverride = Sentinel.unset,
    bool? autoUpdate,
    Object? lastUpdatedAt = Sentinel.unset,
    int? sortIndex,
    bool? isCollapsed,
  }) {
    return Subscription(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      userInfo: identical(userInfo, Sentinel.unset)
          ? this.userInfo
          : userInfo as SubscriptionUserInfo?,
      profileTitle: identical(profileTitle, Sentinel.unset)
          ? this.profileTitle
          : profileTitle as String?,
      announcement: identical(announcement, Sentinel.unset)
          ? this.announcement
          : announcement as String?,
      profileWebPageUrl: identical(profileWebPageUrl, Sentinel.unset)
          ? this.profileWebPageUrl
          : profileWebPageUrl as Uri?,
      supportUrl: identical(supportUrl, Sentinel.unset)
          ? this.supportUrl
          : supportUrl as Uri?,
      updateIntervalHours: identical(updateIntervalHours, Sentinel.unset)
          ? this.updateIntervalHours
          : updateIntervalHours as int?,
      userAgentOverride: identical(userAgentOverride, Sentinel.unset)
          ? this.userAgentOverride
          : userAgentOverride as String?,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      lastUpdatedAt: identical(lastUpdatedAt, Sentinel.unset)
          ? this.lastUpdatedAt
          : lastUpdatedAt as DateTime?,
      sortIndex: sortIndex ?? this.sortIndex,
      isCollapsed: isCollapsed ?? this.isCollapsed,
    );
  }

  /// Serialises the subscription, secret [url] included.
  JsonMap toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'url': url.toString(),
        'userInfo': userInfo?.toJson(),
        'profileTitle': profileTitle,
        'announcement': announcement,
        'profileWebPageUrl': profileWebPageUrl?.toString(),
        'supportUrl': supportUrl?.toString(),
        'updateIntervalHours': updateIntervalHours,
        'userAgentOverride': userAgentOverride,
        'autoUpdate': autoUpdate,
        'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
        'sortIndex': sortIndex,
        'isCollapsed': isCollapsed,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subscription &&
          other.id == id &&
          other.name == name &&
          other.url == url &&
          other.userInfo == userInfo &&
          other.profileTitle == profileTitle &&
          other.announcement == announcement &&
          other.profileWebPageUrl == profileWebPageUrl &&
          other.supportUrl == supportUrl &&
          other.updateIntervalHours == updateIntervalHours &&
          other.userAgentOverride == userAgentOverride &&
          other.autoUpdate == autoUpdate &&
          other.lastUpdatedAt == lastUpdatedAt &&
          other.sortIndex == sortIndex &&
          other.isCollapsed == isCollapsed;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        url,
        userInfo,
        profileTitle,
        announcement,
        profileWebPageUrl,
        supportUrl,
        updateIntervalHours,
        userAgentOverride,
        autoUpdate,
        lastUpdatedAt,
        sortIndex,
        isCollapsed,
      );

  /// Never prints [url] in full.
  @override
  String toString() => 'Subscription($id, $name, ${Redact.uri(url)})';
}
