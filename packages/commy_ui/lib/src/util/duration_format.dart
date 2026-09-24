import 'dart:ui' show Locale;

/// Formats durations for display.
///
/// Digits and colons, plus one unit symbol that follows the locale the way
/// `CommyByteFormat`'s do — a symbol, not a string, so it can live in a
/// package that owns no strings.
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

  /// Formats a round trip as a whole number of milliseconds, `42 ms` — or
  /// `42 мс` for [locale] `ru`.
  static String milliseconds(Duration value, {Locale? locale}) {
    final symbol = locale?.languageCode == 'ru'
        ? cyrillicMillisecondSymbol
        : millisecondSymbol;
    return '${value.inMilliseconds} $symbol';
  }

  /// Symbol appended by [milliseconds].
  static const String millisecondSymbol = 'ms';

  /// The same symbol as Russian writes it. A Russian row read `110 ms` next
  /// to `1,3 ТБ` and `Б/с` on the same screen.
  static const String cyrillicMillisecondSymbol = 'мс';

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
