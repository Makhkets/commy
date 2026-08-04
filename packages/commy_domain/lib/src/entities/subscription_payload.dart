import 'package:commy_domain/src/entities/subscription.dart';

/// The raw answer of a subscription server, headers already parsed.
///
/// Panels put the interesting metadata in headers, not in the body:
/// `subscription-userinfo`, `profile-update-interval`, `profile-title` and
/// `profile-web-page-url` (docs/06-data-model.md). Whatever is missing stays
/// `null` — we show nothing rather than invent numbers.
class SubscriptionPayload {
  /// Creates a payload.
  const SubscriptionPayload({
    required this.body,
    this.userInfo,
    this.profileTitle,
    this.profileWebPageUrl,
    this.supportUrl,
    this.updateIntervalHours,
  });

  /// The response body, exactly as received. May be base64, YAML or JSON.
  final String body;

  /// Parsed `subscription-userinfo` header.
  final SubscriptionUserInfo? userInfo;

  /// Parsed `profile-title` header, already decoded from base64.
  final String? profileTitle;

  /// Parsed `profile-web-page-url` header.
  final Uri? profileWebPageUrl;

  /// Support contact the panel advertises, when it does.
  final Uri? supportUrl;

  /// Parsed `profile-update-interval` header, in hours.
  final int? updateIntervalHours;

  /// Applies everything the panel told us onto [subscription].
  ///
  /// Only overwrites fields the panel actually reported, so a server that
  /// stops sending a header does not erase what we already know.
  Subscription applyTo(Subscription subscription) => subscription.copyWith(
        userInfo: userInfo ?? subscription.userInfo,
        profileTitle: profileTitle ?? subscription.profileTitle,
        profileWebPageUrl:
            profileWebPageUrl ?? subscription.profileWebPageUrl,
        supportUrl: supportUrl ?? subscription.supportUrl,
        updateIntervalHours:
            updateIntervalHours ?? subscription.updateIntervalHours,
      );

  /// Never prints [body]: it is a list of links with credentials in them.
  @override
  String toString() =>
      'SubscriptionPayload(${body.length} bytes, title: $profileTitle)';
}
