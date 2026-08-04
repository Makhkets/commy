/// Formats durations for display.
///
/// Digits and colons only — nothing here needs translating, which is why it
/// can live in a package that owns no strings.
abstract final class CommyDurationFormat {
  /// Placeholder shown where a duration is not known yet.
  static const String unknown = '—';

  /// Formats a session length as `HH:MM:SS`, for example `00:12:47`.
  ///
  /// Hours are not clamped: a tunnel that has been up for three days shows
  /// `72:00:00` rather than wrapping round to zero.
  static String clock(Duration value) {
    final total = value.isNegative ? Duration.zero : value;
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(Duration.minutesPerHour);
    final seconds = total.inSeconds.remainder(Duration.secondsPerMinute);
    return '${_pad(hours)}:${_pad(minutes)}:${_pad(seconds)}';
  }

  /// Formats a round trip as a whole number of milliseconds, `42 ms`.
  static String milliseconds(Duration value) =>
      '${value.inMilliseconds} $millisecondSymbol';

  /// Symbol appended by [milliseconds].
  static const String millisecondSymbol = 'ms';

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
