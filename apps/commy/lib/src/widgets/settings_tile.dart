import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// The uppercase label that names a group of rows.
///
/// Matches the `РАЗДЕЛЫ` / `ПОДКЛЮЧЕНИЕ` headings in
/// docs/design-refs/08-settings.png.
class SectionLabel extends StatelessWidget {
  /// Creates the label.
  const SectionLabel(this.text, {super.key});

  /// What the group is called.
  final String text;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.s4,
        end: spacing.s4,
        top: spacing.s5,
        bottom: spacing.s2,
      ),
      child: Text(
        text.toUpperCase(),
        style: context.typography.label.copyWith(
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}

/// A rounded card that holds a run of [SettingsTile]s.
class SettingsSection extends StatelessWidget {
  /// Creates the card.
  const SettingsSection({
    required this.children,
    this.tone = CommyTone.neutral,
    super.key,
  });

  /// The rows.
  final List<Widget> children;

  /// Which wash the card sits on. Neutral means the plain surface.
  final CommyTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final background =
        tone == CommyTone.neutral ? colors.bgSurface : tone.wash(colors);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: context.radii.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < children.length; index++) ...<Widget>[
              if (index > 0) const CommyDivider(indent: dividerIndent),
              children[index],
            ],
          ],
        ),
      ),
    );
  }

  /// Lines the divider up with the text, not with the icon.
  ///
  /// Public because a long run of rows cannot go through this widget: a
  /// section builds all of its children at once, and the app list is
  /// hundreds of rows long. That list draws the same card and the same
  /// dividers from a lazy sliver, and it has to line them up identically.
  static const double dividerIndent = 56;
}

/// One row inside a [SettingsSection].
///
/// Exactly one of [value], [trailing] and [onTap]-with-a-chevron ends the row;
/// the widget does not try to render two trailing things at once because the
/// designs never do.
class SettingsTile extends StatelessWidget {
  /// Creates the row.
  const SettingsTile({
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.isMonospaceSubtitle = false,
    this.selected,
    this.checked,
    this.tone = CommyTone.neutral,
    super.key,
  }) : assert(
          selected == null || checked == null,
          'a row is either one of several choices or a single tick, not both',
        );

  /// The main label.
  final String title;

  /// The quiet line under it.
  final String? subtitle;

  /// The glyph on the leading edge.
  final IconData? icon;

  /// A short right-aligned value, e.g. `Выбрано 7`.
  final String? value;

  /// A control on the trailing edge, e.g. a switch.
  final Widget? trailing;

  /// Makes the row tappable and draws a chevron.
  final VoidCallback? onTap;

  /// Renders [subtitle] in the monospace face, for hosts and versions.
  final bool isMonospaceSubtitle;

  /// Whether this row is the chosen one of a set of mutually exclusive rows.
  ///
  /// Pass it for a radio row and leave it `null` for everything else. It is
  /// what makes the row announce itself the way `RadioListTile` does — name,
  /// state, one stop — instead of leaving a screen reader with two: the name
  /// as prose and the radio beside it repeating the name with the state.
  ///
  /// Merging alone could not do it. The row and the radio each had a tap
  /// handler, and two tap actions do not fold into one node, so the radio
  /// stayed a second stop with nothing to say. The row has to own both the
  /// state and the tap, and [trailing] becomes the picture of the state.
  final bool? selected;

  /// Whether this row's tick box is ticked.
  ///
  /// [selected] for one of several mutually exclusive choices, this for an
  /// independent one. Same effect on the row — it owns the state, the tap and
  /// the announcement — minus the "one of a group" part, which is what a
  /// screen reader uses to say "1 of 4".
  final bool? checked;

  /// Colours the title, for rows that carry a status.
  final CommyTone tone;

  /// Width [text] needs in [style], at the text scale it will be drawn with.
  double _widthOf(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final subtitleText = subtitle;
    final valueText = value;
    final control = trailing;

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CommySizes.minTapTarget),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.s4,
          vertical: spacing.s3,
        ),
        // The row is measured because one of its children cannot be trusted
        // to be short. `value` is whatever the screen has to report, and on
        // the routing screen that is the resolver: set a DoH address and
        // "https://dns.example.com/dns-query · prefer_ipv4" arrives, 314pt
        // of it, which overflowed a 390pt phone by 60 pixels at the system
        // font size — a striped bar across a settings screen for a
        // configuration nothing is wrong with.
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Side by side until the title stops fitting, and then stacked.
            // Half the row was enough to stop the resolver overflowing, and
            // not enough to keep "Переименовать" a word: at the system font
            // turned up to 1.6 the title column came out 70pt wide and the
            // row read "Пер / еим / ено / вать". A value under the title
            // costs one line; a title spelled downwards costs the row.
            final fixed =
                (icon == null ? 0.0 : CommySizes.iconControl + spacing.s3) +
                    (valueText == null ? 0.0 : spacing.s3) +
                    (onTap != null && control == null
                        ? CommySizes.iconControl + spacing.s2
                        : 0.0);
            final room = constraints.maxWidth - fixed;
            final stackValue = valueText != null &&
                control == null &&
                _widthOf(context, title, type.body) +
                        _widthOf(context, valueText, type.caption) >
                    room;

            return Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: CommySizes.iconControl,
                    color: colors.textSecondary,
                  ),
                  SizedBox(width: spacing.s3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: type.body.copyWith(
                          color: tone == CommyTone.neutral
                              ? colors.textPrimary
                              : tone.foreground(colors),
                        ),
                      ),
                      if (subtitleText != null) ...<Widget>[
                        SizedBox(height: spacing.s1),
                        Text(
                          subtitleText,
                          style: (isMonospaceSubtitle
                                  ? type.monoSmall
                                  : type.caption)
                              .copyWith(color: colors.textTertiary),
                        ),
                      ],
                      if (stackValue) ...<Widget>[
                        SizedBox(height: spacing.s1),
                        Text(
                          valueText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption
                              .copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (valueText != null && !stackValue) ...<Widget>[
                  SizedBox(width: spacing.s3),
                  ConstrainedBox(
                    // Half the row, and not a pixel more. A short value still
                    // takes exactly its own width, so nothing that fits today
                    // moves; a long one gives way to the title, which is what
                    // names the row.
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
                if (control != null) ...<Widget>[
                  SizedBox(width: spacing.s3),
                  // A choice row announces its own state, so the radio or the
                  // tick inside it is a drawing. Anything else — a switch —
                  // still speaks.
                  if (selected == null && checked == null)
                    control
                  else
                    ExcludeSemantics(child: control),
                ],
                if (onTap != null && control == null) ...<Widget>[
                  SizedBox(width: spacing.s2),
                  Icon(
                    CommyIcons.chevronRight,
                    size: CommySizes.iconControl,
                    color: colors.textTertiary,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );

    if (onTap == null) {
      return row;
    }
    final choice = selected ?? checked;
    final isChoice = choice != null;
    final tappable = Semantics(
      // `InkWell` gives the node a tap action but not the button flag, so a
      // screen reader read "Маршрутизация" as a line of prose and never said
      // it could be opened. Nine of the ten rows on the settings screen were
      // like that.
      //
      // Only the navigating variant claims it. A row that ends in a switch is
      // announced by the switch, which carries the state as well as the name,
      // and calling the row a button on top of that offers two different
      // things for one row.
      button: trailing == null && !isChoice,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
    if (!isChoice) {
      return tappable;
    }
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: selected != null,
        checked: choice,
        child: tappable,
      ),
    );
  }
}
