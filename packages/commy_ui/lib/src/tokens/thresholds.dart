import 'package:commy_domain/commy_domain.dart';

/// Numeric thresholds at which a component changes colour.
///
/// They are tokens for the same reason colours are: a threshold that lives in
/// two files drifts apart. Where the domain already owns the number — the
/// quota ratio at which a subscription counts as nearly spent — it is read
/// from there instead of being re-declared.
abstract final class CommyThresholds {
  /// Below this round trip a node is "fast" and gets `status/connected`.
  static const Duration latencyFast = Duration(milliseconds: 100);

  /// Below this round trip a node is "medium" and gets `status/connecting`.
  /// At or above it, `status/error`.
  static const Duration latencySlow = Duration(milliseconds: 300);

  /// Share of quota at which the bar turns amber.
  static const double quotaWarn = 0.75;

  /// Share of quota at which the bar turns red.
  ///
  /// Same number the domain uses for [SubscriptionUserInfo.isNearQuota], read
  /// from there so the bar and the warning text can never disagree.
  static const double quotaCritical = SubscriptionUserInfo.nearQuotaRatio;

  /// How long the traffic sparkline looks back.
  static const Duration chartWindow = Duration(seconds: 60);
}
