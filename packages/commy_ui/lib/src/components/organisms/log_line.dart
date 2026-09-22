import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:flutter/material.dart';

/// One line of the core log.
///
/// Named `LogLineView` and not `LogLine` on purpose: [LogLine] is the domain
/// entity this widget draws, and an app that imports both packages would
/// otherwise have to prefix one of them.
///
/// Three rules shape it. Monospace, because a log is read in columns —
/// timestamps and levels have to line up or the eye cannot scan them. Colour
/// by level, but always next to the three-letter level code, so the severity
/// survives a colour-blind reader and a black-and-white screenshot. And
/// selectable, because the first thing anyone does with a log is copy the one
/// line that matters into a message to whoever runs their server.
///
/// The text is shown as the core produced it. Redaction happens on export
/// (rule R3): what is on screen is for the person holding the phone.
class LogLineView extends StatelessWidget {
  /// Creates a log line.
  const LogLineView({
    required this.line,
    this.isSelectable = true,
    this.maxLines = defaultMaxLines,
    super.key,
  });

  /// How many lines one record is allowed to take before it is cut off.
  ///
  /// Six, and the number is the point of this parameter. sing-box logs a
  /// rejected configuration by echoing it, and a 1200-character token wrapped
  /// to 620pt — three quarters of a phone screen for one record, with two
  /// rows of four visible in the viewport. A log you have to scroll past is a
  /// log nobody reads, and the screen already offers the whole text two ways:
  /// copy, and export to a file, both redacted (rule R3).
  static const int defaultMaxLines = 6;

  /// The record to draw.
  final LogLine line;

  /// Whether the text can be selected and copied. Off is for previews and
  /// golden tests, where a selection handle is noise.
  final bool isSelectable;

  /// Lines to show before cutting the record off. `null` shows all of it.
  final int? maxLines;

  /// Three-letter code shown in place of the level name.
  ///
  /// Fixed width by design: `INF` and `WRN` occupy the same space, so the
  /// messages start on the same column.
  String get levelCode => switch (line.level) {
        LogLevel.trace => 'TRC',
        LogLevel.debug => 'DBG',
        LogLevel.info => 'INF',
        LogLevel.warn => 'WRN',
        LogLevel.error => 'ERR',
        LogLevel.fatal => 'FTL',
      };

  /// Wall-clock time of the record as `HH:MM:SS`.
  ///
  /// Date-free: a log view covers one session, and a date on every line would
  /// push the message off the screen.
  String get timestamp {
    final at = line.at;
    return '${_pad(at.hour)}:${_pad(at.minute)}:${_pad(at.second)}';
  }

  /// Colour the level code is drawn in.
  Color levelColor(CommyColors colors) => switch (line.level) {
        LogLevel.trace => colors.textDisabled,
        LogLevel.debug => colors.textTertiary,
        LogLevel.info => colors.textSecondary,
        LogLevel.warn => colors.statusConnecting,
        LogLevel.error || LogLevel.fatal => colors.statusError,
      };

  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final tag = line.tag;
    final severity = levelColor(colors);
    final isFailure =
        line.level == LogLevel.error || line.level == LogLevel.fatal;

    final span = TextSpan(
      style: type.mono.copyWith(color: colors.textPrimary),
      children: <InlineSpan>[
        TextSpan(
          text: '$timestamp ',
          style: type.mono.copyWith(color: colors.textTertiary),
        ),
        TextSpan(
          text: '$levelCode ',
          style: type.monoStrong.copyWith(color: severity),
        ),
        if (tag != null)
          TextSpan(
            text: '$tag ',
            style: type.mono.copyWith(color: colors.textTertiary),
          ),
        TextSpan(
          text: line.message,
          style: type.mono.copyWith(
            color: isFailure ? colors.statusError : colors.textPrimary,
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s3,
        vertical: spacing.s1,
      ),
      child: isSelectable
          ? SelectableText.rich(
              span,
              // `minLines` is not decoration. Without it `SelectableText`
              // reserves the full `maxLines` height for every record, and a
              // one-line "sing-box started" drew as 120pt of mostly nothing.
              minLines: 1,
              maxLines: maxLines,
            )
          : Text.rich(
              span,
              maxLines: maxLines,
              overflow:
                  maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
    );
  }
}
