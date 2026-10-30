import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/tag_colors.dart';
import 'package:flutter/material.dart';

/// One word of the line under a server name — `VLESS`, `Reality`, `TCP` —
/// and the hue it is drawn in.
@immutable
class NodeTag {
  /// Creates a tag. Without a [hue] it is a plain caption.
  const NodeTag(this.label, {this.hue = CommyTagHue.neutral});

  /// The word. Wire names are not translated; anything else arrives
  /// translated.
  final String label;

  /// Its colour family.
  final CommyTagHue hue;

  @override
  bool operator ==(Object other) =>
      other is NodeTag && other.label == label && other.hue == hue;

  @override
  int get hashCode => Object.hash(label, hue);

  @override
  String toString() => 'NodeTag($label, ${hue.name})';
}

/// `VLESS Reality TCP`, each word in its own hue — the way INCY draws it,
/// which the owner asked for — with a 6 dp gap between the words instead of
/// the middle dots it used to have: the hues already tell the words apart,
/// and metadata is not joined with dots (docs/04-design-system.md §2.2).
///
/// One line, ellipsised, in a list row: a long flow name must not push the
/// row taller. A header with room to grow — the server's own menu — passes
/// `maxLines: null` and wraps instead, so the whole line can be read there at
/// any text size. Either way it is read out as one phrase, joined the way it
/// is drawn.
///
/// [muted] draws every word in [mutedColor] instead of its hue. A server that
/// stopped answering is grey all over — flag, name and this line — and a
/// bright `VLESS` on a dead row would argue with that.
class NodeTagLine extends StatelessWidget {
  /// Creates the line.
  const NodeTagLine({
    required this.tags,
    this.muted = false,
    this.mutedColor,
    this.maxLines = 1,
    super.key,
  });

  /// What sits between two tags when the line is read out or copied as text.
  /// On screen the gap is `space/1.5`, not a character.
  static const String separator = ' ';

  /// The words, in order.
  final List<NodeTag> tags;

  /// Whether to drop the hues.
  final bool muted;

  /// The colour of a muted line. `ink-2` when `null`.
  final Color? mutedColor;

  /// How many lines the words may take, ellipsised after the last; `null`
  /// lets them wrap freely.
  final int? maxLines;

  /// The line as plain text, as it is announced.
  String get text => tags.map((tag) => tag.label).join(separator);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tagColors = context.tagColors;
    final base = context.typography.caption.copyWith(
      color: mutedColor ?? colors.textSecondary,
    );

    final gap = context.spacing.s15;
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          for (var index = 0; index < tags.length; index++) ...<InlineSpan>[
            if (index > 0) WidgetSpan(child: SizedBox(width: gap)),
            TextSpan(
              text: tags[index].label,
              style: muted || tags[index].hue == CommyTagHue.neutral
                  ? null
                  : TextStyle(
                      color: tagColors.of(tags[index].hue, colors),
                    ),
            ),
          ],
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      semanticsLabel: text,
    );
  }
}
