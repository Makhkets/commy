import 'package:commy/gen/strings.g.dart';
import 'package:flutter/widgets.dart';

/// The Flutter locale a set of translations is written in.
///
/// For the formatters that live below `slang` — byte counts in `commy_ui`
/// take a `Locale`, not a `Translations` — so that a number and the sentence
/// around it are always in the same language.
extension TranslationsLocale on Translations {
  /// The locale these strings are in.
  Locale get flutterLocale => $meta.locale.flutterLocale;
}
