import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/secure/secret_keys.dart';
import 'package:commy_data/src/util/json_text.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Row ⇄ `Subscription`, with the URL kept out of the row.
abstract final class SubscriptionMapper {
  /// Builds a domain subscription out of a row and its secret URL.
  ///
  /// [url] is `null` when the keystore has nothing for this id — the app was
  /// reinstalled over its own data directory, or the user cleared credentials
  /// from the system settings. The subscription is still shown, with the
  /// redacted URL the row carries, and a refresh will fail with a storage
  /// failure the user can read. Dropping the row instead would make a list of
  /// servers vanish with no explanation, which is worse.
  static Subscription toDomain(SubscriptionRow row, {Uri? url}) {
    final userInfoJson = row.userInfoJson;
    return Subscription(
      id: row.id,
      name: row.name,
      url: url ?? Uri.parse(row.redactedUrl),
      userInfo: userInfoJson == null
          ? null
          : SubscriptionUserInfo.fromJson(JsonText.decodeOrEmpty(userInfoJson)),
      profileTitle: row.profileTitle,
      announcement: row.announcement,
      profileWebPageUrl: _uriOrNull(row.profileWebPageUrl),
      supportUrl: _uriOrNull(row.supportUrl),
      updateIntervalHours: row.updateIntervalHours,
      userAgentOverride: row.userAgentOverride,
      autoUpdate: row.autoUpdate,
      lastUpdatedAt: row.lastUpdatedAt,
      sortIndex: row.sortIndex,
      isCollapsed: row.isCollapsed,
    );
  }

  /// Builds the row half of [subscription]. The URL is *not* in the result.
  static SubscriptionRowsCompanion toCompanion(Subscription subscription) {
    final userInfo = subscription.userInfo;
    return SubscriptionRowsCompanion(
      id: Value<String>(subscription.id),
      name: Value<String>(subscription.name),
      urlRef: Value<String>(SecretKeys.subscriptionUrl(subscription.id)),
      redactedUrl: Value<String>(
        Redact.uriValue(subscription.url).toString(),
      ),
      userInfoJson: Value<String?>(
        userInfo == null ? null : JsonText.encode(userInfo.toJson()),
      ),
      profileTitle: Value<String?>(subscription.profileTitle),
      announcement: Value<String?>(subscription.announcement),
      profileWebPageUrl: Value<String?>(
        subscription.profileWebPageUrl?.toString(),
      ),
      supportUrl: Value<String?>(subscription.supportUrl?.toString()),
      updateIntervalHours: Value<int?>(subscription.updateIntervalHours),
      userAgentOverride: Value<String?>(subscription.userAgentOverride),
      autoUpdate: Value<bool>(subscription.autoUpdate),
      lastUpdatedAt: Value<DateTime?>(subscription.lastUpdatedAt),
      sortIndex: Value<int>(subscription.sortIndex),
      isCollapsed: Value<bool>(subscription.isCollapsed),
    );
  }

  static Uri? _uriOrNull(String? raw) =>
      raw == null || raw.isEmpty ? null : Uri.tryParse(raw);
}
