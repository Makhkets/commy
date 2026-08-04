import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/services.dart';

/// The system clipboard behind the domain's [ClipboardPort].
///
/// The clipboard is read in exactly one place — when the import sheet opens —
/// and what was found is shown before anything is pasted
/// (docs/05-ux-flows.md, "Проверка буфера обмена"). Nothing polls it in the
/// background.
class FlutterClipboard implements ClipboardPort {
  /// Creates the adapter.
  const FlutterClipboard();

  @override
  Future<Result<String?, CommyFailure>> read() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return Ok<String?, CommyFailure>(data?.text);
    } on Object catch (error, stackTrace) {
      return Err<String?, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }

  @override
  Future<Result<void, CommyFailure>> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error, stackTrace) {
      return Err<void, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
