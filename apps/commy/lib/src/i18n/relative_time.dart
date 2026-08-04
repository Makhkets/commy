import 'package:commy/gen/strings.g.dart';

/// Coarse, translated durations: `2 ч`, `15 мин`, `40 с`.
///
/// Deliberately not `intl`'s relative formatting. What the subscription header
/// needs is one unit, rounded down, and the same shape in both languages — not
/// "about two hours ago" in one and "2 ч назад" in the other.
abstract final class RelativeTime {
  /// The largest whole unit that fits in [value].
  static String coarse(Duration value, Translations t) {
    final absolute = value.isNegative ? -value : value;
    if (absolute.inDays >= 1) {
      return t.time.days(count: absolute.inDays);
    }
    if (absolute.inHours >= 1) {
      return t.time.hours(count: absolute.inHours);
    }
    if (absolute.inMinutes >= 1) {
      return t.time.minutes(count: absolute.inMinutes);
    }
    return t.time.seconds(count: absolute.inSeconds);
  }

  /// Whole hours, for a refresh interval that is always configured in hours.
  static String hours(Duration value, Translations t) =>
      t.time.hours(count: value.inHours);
}
