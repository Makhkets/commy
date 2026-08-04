import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:commy_core/src/logging/log_redaction.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';

/// The only way anything in this repository writes a diagnostic line.
///
/// `print` is banned (CLAUDE.md, "Конвенции кода"), and not for tidiness: a
/// `print` goes to the platform console unredacted, survives in `logcat` after
/// the app is gone, and is invisible to the log screen the user actually looks
/// at. Everything written here lands in three places instead — a bounded ring
/// buffer, a broadcast stream, and a sink that only speaks in debug builds.
///
/// ## Redaction happens on the way *in*
///
/// This is a deliberate departure from the general R3 rule that redaction sits
/// on the output layer. That rule is written for the *core* log, which
/// `commy_data` keeps raw in `LogRepository` and redacts per destination — the
/// live view shows more than an export does, and that difference is useful.
///
/// [AppLogger] has no second gate: its buffer is what a developer copies out of
/// a debug build and what [export] renders verbatim. So a message is scrubbed
/// by `redact` *before* it is stored or emitted, and a credential never exists
/// in memory here at all. The cost is that the live view cannot show more than
/// the export; for the app's own lines that is not a loss.
///
/// ## Not a singleton
///
/// One instance is created in the composition root and handed down. There is no
/// `AppLogger.instance`: a global would be impossible to reset between tests
/// and would keep a stream controller alive for the life of the process.
class AppLogger {
  /// Creates a logger.
  ///
  /// [capacity] bounds the ring buffer. [minimumLevel] drops quieter lines
  /// before they cost anything. [redact] defaults to [DefaultLogRedaction] and
  /// is the seam through which the app injects the wider redactor from
  /// `commy_data`. [clock] and [sink] exist so tests can be deterministic and
  /// silent.
  AppLogger({
    int capacity = defaultCapacity,
    this.minimumLevel = LogLevel.debug,
    LogRedaction redact = DefaultLogRedaction.apply,
    DateTime Function()? clock,
    void Function(LogLine line)? sink,
  })  : assert(capacity > 0, 'capacity must be positive'),
        _capacity = capacity,
        _redact = redact,
        _clock = clock ?? DateTime.now,
        _sink = sink ?? debugSink;

  /// How many lines the ring buffer keeps by default.
  ///
  /// Enough to cover a connect attempt and the minute after it, small enough
  /// that the whole thing fits in a bug report without truncation.
  static const int defaultCapacity = 500;

  /// Name [debugSink] passes to the platform log viewer.
  static const String debugSinkName = 'commy';

  final int _capacity;
  final LogRedaction _redact;
  final DateTime Function() _clock;
  final void Function(LogLine line) _sink;
  final ListQueue<LogLine> _buffer = ListQueue<LogLine>();
  final StreamController<LogLine> _controller =
      StreamController<LogLine>.broadcast();

  bool _disposed = false;

  /// Lines quieter than this are dropped without being stored or emitted.
  ///
  /// Mutable so the log screen can raise or lower the threshold at runtime,
  /// following `AppSettings.logLevel`, without rebuilding the logger and losing
  /// the buffer that is the whole reason the user opened that screen.
  LogLevel minimumLevel;

  /// Every line from the moment of subscription onwards.
  ///
  /// Broadcast, so a late subscriber sees nothing that came before it. That is
  /// what [buffer] is for: read it once on attach, then follow the stream.
  Stream<LogLine> get lines => _controller.stream;

  /// The ring buffer, oldest line first. Already redacted.
  List<LogLine> get buffer => List<LogLine>.unmodifiable(_buffer);

  /// How many lines the buffer is holding.
  int get length => _buffer.length;

  /// Whether [dispose] has run. A disposed logger silently ignores writes.
  bool get isDisposed => _disposed;

  /// Writes a line at [level].
  ///
  /// [error] and [stackTrace] are folded into the message before redaction, so
  /// an exception carrying a subscription URL in its text cannot slip past.
  void log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_disposed || !level.passes(minimumLevel)) {
      return;
    }
    add(
      LogLine(
        level: level,
        message: _compose(message, error, stackTrace),
        at: _clock(),
        tag: tag,
      ),
    );
  }

  /// Per-packet noise. Off in every build the user ever sees.
  void trace(String message, {String? tag}) =>
      log(LogLevel.trace, message, tag: tag);

  /// Detail that is useful while chasing something.
  void debug(String message, {String? tag}) =>
      log(LogLevel.debug, message, tag: tag);

  /// Normal operation worth a line.
  void info(String message, {String? tag}) =>
      log(LogLevel.info, message, tag: tag);

  /// Something looks wrong but the app carried on.
  void warn(String message, {String? tag, Object? error}) =>
      log(LogLevel.warn, message, tag: tag, error: error);

  /// An operation failed.
  void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        LogLevel.error,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );

  /// The app cannot continue doing what it was asked to do.
  void fatal(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        LogLevel.fatal,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );

  /// Files an already-built [line], redacting it first.
  ///
  /// This is the door the core log stream comes through: the native side hands
  /// up raw text (`docs/wire-protocol.md`, "/logs"), and it gets the same
  /// treatment as anything the app writes itself.
  void add(LogLine line) {
    if (_disposed || !line.level.passes(minimumLevel)) {
      return;
    }
    final safe = line.copyWith(message: _redact(line.message));
    _buffer.addLast(safe);
    while (_buffer.length > _capacity) {
      _buffer.removeFirst();
    }
    _sink(safe);
    if (_controller.hasListener) {
      _controller.add(safe);
    }
  }

  /// Renders the buffer as text, newest line last.
  ///
  /// Safe to attach to an issue as it stands: nothing unredacted ever entered
  /// the buffer.
  String export() => _buffer.map(format).join('\n');

  /// Empties the buffer. The stream is left alone.
  void clear() => _buffer.clear();

  /// Closes the stream and drops the buffer. Further writes are ignored.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _buffer.clear();
    await _controller.close();
  }

  /// One line, rendered: `12:04:31.007 W router  message`.
  static String format(LogLine line) {
    final time = line.at.toLocal();
    final clock = '${_pad(time.hour, 2)}:${_pad(time.minute, 2)}:'
        '${_pad(time.second, 2)}.${_pad(time.millisecond, 3)}';
    final tag = line.tag == null ? '' : ' ${line.tag}';
    return '$clock ${line.level.wireName.toUpperCase()}$tag ${line.message}';
  }

  /// The default sink: the platform log viewer, and only outside release.
  ///
  /// Guarded by [kReleaseMode] rather than by an assert so that a release build
  /// carries no path from a log line to the system log at all. Nothing here
  /// reaches the network — rule R1 is about outgoing requests, and there are
  /// none in this file.
  static void debugSink(LogLine line) {
    if (kReleaseMode) {
      return;
    }
    developer.log(
      line.message,
      time: line.at,
      name: line.tag == null ? debugSinkName : '$debugSinkName.${line.tag}',
      level: _developerLevel(line.level),
    );
  }

  String _compose(String message, Object? error, StackTrace? stackTrace) {
    if (error == null && stackTrace == null) {
      return message;
    }
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write(': $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }

  /// Maps our level onto the `dart:developer` scale, which is `package:logging`
  /// numbering: FINEST 300, FINE 500, INFO 800, WARNING 900, SEVERE 1000,
  /// SHOUT 1200.
  static int _developerLevel(LogLevel level) => switch (level) {
        LogLevel.trace => 300,
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
        LogLevel.fatal => 1200,
      };

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}
