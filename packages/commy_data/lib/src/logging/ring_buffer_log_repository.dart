import 'dart:async';
import 'dart:collection';

import 'package:commy_data/src/logging/log_redactor.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';

/// The log buffer, in memory, with rule R3 applied on the way out.
///
/// In memory and not in the database on purpose. A persisted log of every
/// domain the user resolved is a browsing history: exactly the artefact this
/// project promises not to keep (docs/00-vision.md). The buffer dies with the
/// process, which is the correct lifetime for it.
///
/// Lines go in raw and come out redacted:
///
/// * [watch] and [read] apply `LogRedactor.redact` — credentials gone, server
///   addresses kept, because that is what makes the live view usable;
/// * [export] with `redact: true` additionally replaces the user's own server
///   addresses with `[server]`;
/// * [export] with `redact: false` returns the raw buffer and is only ever
///   legitimate right after the user confirmed a dialog spelling out what is in
///   it (docs/09-security-privacy.md, "Как реализовано").
class RingBufferLogRepository implements LogRepository {
  /// Creates the buffer.
  RingBufferLogRepository({
    LogRedactor redactor = const LogRedactor(),
    int capacity = defaultCapacity,
  })  : _redactor = redactor,
        _capacity = capacity < 1 ? 1 : capacity;

  /// How many lines are kept before the oldest is dropped.
  ///
  /// A busy core writes a few lines per second; two thousand is roughly ten
  /// minutes of context, which is what a bug report needs, and a few hundred
  /// kilobytes, which the iOS extension can afford (rule R7).
  static const int defaultCapacity = 2000;

  final LogRedactor _redactor;
  final int _capacity;
  final Queue<LogLine> _buffer = Queue<LogLine>();
  final StreamController<List<LogLine>> _changes =
      StreamController<List<LogLine>>.broadcast();

  var _closed = false;

  /// How many lines are currently buffered.
  int get length => _buffer.length;

  @override
  Stream<List<LogLine>> watch() {
    // `Stream.multi` rather than an `async*` generator: the generator would
    // reach its `yield*` a microtask late, and a broadcast controller drops
    // whatever is added while nobody is listening. A line written in that gap
    // would silently never appear in the log view.
    return Stream<List<LogLine>>.multi((controller) {
      controller.add(_snapshot(forExport: false));
      final subscription = _changes.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<Result<List<LogLine>, CommyFailure>> read({int? limit}) async {
    return StorageGuard.runSync(() {
      final all = _snapshot(forExport: false);
      if (limit == null || limit >= all.length) {
        return all;
      }
      return all.sublist(all.length - (limit < 0 ? 0 : limit));
    });
  }

  @override
  Future<Result<void, CommyFailure>> append(LogLine line) async {
    return StorageGuard.runVoidSync(() {
      _buffer.addLast(line);
      _trim();
      _publish();
    });
  }

  /// Appends several lines and notifies listeners once.
  ///
  /// The core delivers logs in bursts; one notification per burst instead of
  /// one per line is the difference between a scrolling list and a stuttering
  /// one.
  Future<Result<void, CommyFailure>> appendAll(Iterable<LogLine> lines) async {
    return StorageGuard.runVoidSync(() {
      _buffer.addAll(lines);
      _trim();
      _publish();
    });
  }

  @override
  Future<Result<void, CommyFailure>> clear() async {
    return StorageGuard.runVoidSync(() {
      _buffer.clear();
      _publish();
    });
  }

  @override
  Future<Result<String, CommyFailure>> export({required bool redact}) async {
    return StorageGuard.runSync(() {
      final lines = redact ? _snapshot(forExport: true) : _buffer.toList();
      return lines.map(formatLine).join('\n');
    });
  }

  /// Renders one line the way an export writes it.
  ///
  /// Stable and boring on purpose: an exported log is read by a human and
  /// diffed by a maintainer.
  static String formatLine(LogLine line) {
    final tag = line.tag;
    final component = tag == null || tag.isEmpty ? '' : ' [$tag]';
    return '${line.at.toIso8601String()} '
        '${line.level.wireName.toUpperCase()}$component ${line.message}';
  }

  /// Releases the change stream. Call it when the app shuts down.
  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _changes.close();
  }

  void _trim() {
    while (_buffer.length > _capacity) {
      _buffer.removeFirst();
    }
  }

  List<LogLine> _snapshot({required bool forExport}) {
    return List<LogLine>.unmodifiable(
      _buffer.map((line) => _redactor.redactLine(line, forExport: forExport)),
    );
  }

  void _publish() {
    if (_closed || _changes.isClosed) {
      return;
    }
    _changes.add(_snapshot(forExport: false));
  }
}
