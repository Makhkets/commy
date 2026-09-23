import 'package:flutter/widgets.dart';

/// Formats byte counts for display, in the symbols the reader's language uses.
///
/// English reads `1.4 GB` and `37.1 KB/s`; Russian `1,4 ГБ` and `37,1 КБ/с`.
/// The symbols used to be Latin for everyone, on the reasoning that they are
/// "symbols rather than words, identical in ru and en". Russian typography
/// disagrees: the unit is spelled in Cyrillic and the decimal mark is a comma,
/// and on a Russian screen `6.0 GB из 100 GB` reads as a line nobody
/// translated. Seen on the emulator in the owner's language.
///
/// Still not routed through `slang`: this package holds no translations, and
/// a unit symbol is closer to the shape of a digit than to a sentence. The
/// caller says which language it is drawing in — a widget passes
/// `Localizations.maybeLocaleOf(context)` — and anything that is not Russian
/// keeps the Latin form.
abstract final class CommyByteFormat {
  /// Step between units. 1024, because every panel and every core reports
  /// binary multiples while calling them KB.
  static const int step = 1024;

  /// Unit symbols, smallest first.
  static const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  /// The same units as Russian writes them.
  static const List<String> cyrillicUnits = <String>[
    'Б',
    'КБ',
    'МБ',
    'ГБ',
    'ТБ',
  ];

  /// Suffix appended to a rate.
  static const String perSecond = '/s';

  /// The same suffix in Russian.
  static const String cyrillicPerSecond = '/с';

  /// Formats a volume, for example `1.4 GB` — or `1,4 ГБ` for [locale] `ru`.
  static String bytes(int value, {Locale? locale}) {
    final cyrillic = _isCyrillic(locale);
    final symbols = cyrillic ? cyrillicUnits : units;
    final magnitude = value.abs();
    if (magnitude < step) {
      return '$value ${symbols.first}';
    }
    var amount = magnitude.toDouble();
    var unit = 0;
    while (amount >= step && unit < symbols.length - 1) {
      amount /= step;
      unit++;
    }
    final sign = value < 0 ? '-' : '';
    final digits = amount < 10 ? 1 : 0;
    final number = amount.toStringAsFixed(digits);
    return '$sign${cyrillic ? number.replaceAll('.', ',') : number} '
        '${symbols[unit]}';
  }

  /// Formats a rate, for example `37.1 KB/s` — or `37,1 КБ/с` for `ru`.
  static String rate(int bytesPerSecond, {Locale? locale}) =>
      '${bytes(bytesPerSecond, locale: locale)}'
      '${_isCyrillic(locale) ? cyrillicPerSecond : perSecond}';

  static bool _isCyrillic(Locale? locale) => locale?.languageCode == 'ru';
}
