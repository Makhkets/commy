import 'package:drift/drift.dart';

/// Plain metadata of a subscription.
///
/// Rule R2: `Subscription.url` carries the access token, so the URL itself is
/// never a column. [redactedUrl] keeps only what `Redact.uriValue` keeps —
/// scheme, host, port — which is what the UI shows anyway, and the working URL
/// lives in the secure store under [urlRef].
@DataClassName('SubscriptionRow')
class SubscriptionRows extends Table {
  /// Stable identifier.
  TextColumn get id => text()();

  /// Name the user gave it.
  TextColumn get name => text()();

  /// Key under which the full URL lives in the secure store.
  TextColumn get urlRef => text()();

  /// The URL with path and query removed: safe to store, safe to show.
  TextColumn get redactedUrl => text()();

  /// `subscription-userinfo` block as JSON, or `null` when unreported.
  TextColumn get userInfoJson => text().nullable()();

  /// `profile-title` header, already decoded.
  TextColumn get profileTitle => text().nullable()();

  /// Free-text line the panel admin broadcast to their users.
  TextColumn get announcement => text().nullable()();

  /// `profile-web-page-url` header.
  TextColumn get profileWebPageUrl => text().nullable()();

  /// Support contact the panel advertises.
  TextColumn get supportUrl => text().nullable()();

  /// `profile-update-interval` header, in hours.
  IntColumn get updateIntervalHours => integer().nullable()();

  /// User-Agent to send instead of the honest one.
  TextColumn get userAgentOverride => text().nullable()();

  /// Whether the app refreshes this subscription on a timer.
  BoolColumn get autoUpdate => boolean().withDefault(const Constant(false))();

  /// When it was last fetched successfully.
  DateTimeColumn get lastUpdatedAt => dateTime().nullable()();

  /// Position in the list on the main screen.
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// Whether its node group is folded away in the UI.
  BoolColumn get isCollapsed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  String get tableName => 'subscriptions';
}
