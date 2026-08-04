import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/log_line.dart';

/// The ring buffer of log lines and the way out of it.
///
/// Rule R3: lines are stored raw and redacted on the way out. The live view
/// inside the app may show more than an export does, and an unredacted export
/// requires an explicit confirmation that spells out what will be in it.
abstract interface class LogRepository {
  /// The buffer, refreshed as lines arrive.
  Stream<List<LogLine>> watch();

  /// The last [limit] lines, once. `null` means the whole buffer.
  Future<Result<List<LogLine>, CommyFailure>> read({int? limit});

  /// Appends one line.
  Future<Result<void, CommyFailure>> append(LogLine line);

  /// Empties the buffer.
  Future<Result<void, CommyFailure>> clear();

  /// Renders the buffer as text for copying or attaching to an issue.
  ///
  /// [redact] must default to `true` at every call site. Passing `false` is
  /// only legitimate right after the user confirmed a dialog that listed what
  /// the raw log contains.
  Future<Result<String, CommyFailure>> export({required bool redact});
}
