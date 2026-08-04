/// The `YYYY-MM-DD` key the daily traffic table is bucketed by.
///
/// Text rather than a timestamp on purpose: a day is a calendar fact in the
/// user's own timezone, and storing an instant would silently move the boundary
/// whenever the device travels. The chart asks for "Tuesday", not for
/// "the 24 hours after some UTC midnight".
abstract final class DayKey {
  /// Length of a well-formed key. Used by the column constraint.
  static const int length = 10;

  /// The key of the local calendar day [moment] falls into.
  static String of(DateTime moment) {
    final local = moment.isUtc ? moment.toLocal() : moment;
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-$month-$day';
  }

  /// The local midnight a key stands for, or `null` when it is malformed.
  static DateTime? parse(String key) {
    if (key.length != length) {
      return null;
    }
    final year = int.tryParse(key.substring(0, 4));
    final month = int.tryParse(key.substring(5, 7));
    final day = int.tryParse(key.substring(8, 10));
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }
}
