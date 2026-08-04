/// Formats byte counts for display.
///
/// The unit symbols are SI-style abbreviations (`B`, `KB`, `MB`, `GB`, `TB`)
/// and are deliberately **not** routed through `slang`: they are symbols
/// rather than words, they are identical in `ru` and `en`, and this package
/// holds no translations at all. A screen that wants a spelled-out unit
/// formats the number itself and passes the finished string in.
abstract final class CommyByteFormat {
  /// Step between units. 1024, because every panel and every core reports
  /// binary multiples while calling them KB.
  static const int step = 1024;

  /// Unit symbols, smallest first.
  static const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  /// Suffix appended to a rate.
  static const String perSecond = '/s';

  /// Formats a volume, for example `1.4 GB`.
  static String bytes(int value) {
    final magnitude = value.abs();
    if (magnitude < step) {
      return '$value ${units.first}';
    }
    var amount = magnitude.toDouble();
    var unit = 0;
    while (amount >= step && unit < units.length - 1) {
      amount /= step;
      unit++;
    }
    final sign = value < 0 ? '-' : '';
    final digits = amount < 10 ? 1 : 0;
    return '$sign${amount.toStringAsFixed(digits)} ${units[unit]}';
  }

  /// Formats a rate, for example `37.1 KB/s`.
  static String rate(int bytesPerSecond) =>
      '${bytes(bytesPerSecond)}$perSecond';
}
