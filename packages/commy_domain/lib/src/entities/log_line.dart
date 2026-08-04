/// Severity of a log record, ordered from chattiest to loudest.
enum LogLevel {
  /// Everything, including per-packet noise.
  trace(severity: 0, wireName: 'trace'),

  /// Detail useful while debugging.
  debug(severity: 1, wireName: 'debug'),

  /// Normal operation.
  info(severity: 2, wireName: 'info'),

  /// Something looks off but the core carried on.
  warn(severity: 3, wireName: 'warn'),

  /// An operation failed.
  error(severity: 4, wireName: 'error'),

  /// The core cannot continue.
  fatal(severity: 5, wireName: 'fatal');

  const LogLevel({required this.severity, required this.wireName});

  /// Numeric rank used for filtering. Higher is louder.
  final int severity;

  /// Name the sing-box core uses in its own configuration and output.
  final String wireName;

  /// Whether a record of this level passes a [minimum] filter.
  bool passes(LogLevel minimum) => severity >= minimum.severity;

  /// Maps a core level name onto a [LogLevel], or `null` when unknown.
  ///
  /// Accepts the aliases the core emits: `warning` and `panic`.
  static LogLevel? fromWireName(String name) {
    final normalised = name.trim().toLowerCase();
    if (normalised == 'warning') {
      return LogLevel.warn;
    }
    if (normalised == 'panic') {
      return LogLevel.fatal;
    }
    for (final level in LogLevel.values) {
      if (level.wireName == normalised) {
        return level;
      }
    }
    return null;
  }
}

/// One line of the core or app log.
///
/// [message] is stored raw. Redaction happens on the output layer, not here:
/// the live view inside the app shows more than an export does (rule R3, see
/// docs/09-security-privacy.md).
class LogLine {
  /// Creates a log line.
  const LogLine({
    required this.level,
    required this.message,
    required this.at,
    this.tag,
  });

  /// Severity.
  final LogLevel level;

  /// Raw text. Never export without redacting first.
  final String message;

  /// When the line was produced.
  final DateTime at;

  /// Component that produced it, when the core said so.
  final String? tag;

  /// Returns a copy with the given fields replaced.
  LogLine copyWith({
    LogLevel? level,
    String? message,
    DateTime? at,
    String? tag,
  }) {
    return LogLine(
      level: level ?? this.level,
      message: message ?? this.message,
      at: at ?? this.at,
      tag: tag ?? this.tag,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogLine &&
          other.level == level &&
          other.message == message &&
          other.at == at &&
          other.tag == tag;

  @override
  int get hashCode => Object.hash(level, message, at, tag);

  /// Deliberately omits [message]: it may carry credentials.
  @override
  String toString() => 'LogLine(${level.name}, $at, $tag)';
}
