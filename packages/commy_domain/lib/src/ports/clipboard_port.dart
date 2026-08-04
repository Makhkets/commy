import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';

/// Access to the system clipboard.
///
/// Read only when the user opens the import screen, never in the background,
/// and always show what was found before pasting it
/// (docs/05-ux-flows.md, scenario 1).
abstract interface class ClipboardPort {
  /// Current clipboard text, or `null` when there is none.
  Future<Result<String?, CommyFailure>> read();

  /// Puts [text] on the clipboard.
  Future<Result<void, CommyFailure>> write(String text);
}
