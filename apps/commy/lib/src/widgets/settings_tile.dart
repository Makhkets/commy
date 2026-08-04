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
              if (index > 0) const CommyDivider(indent: _dividerIndent),
              children[index],
            ],
          ],
        ),
      ),
    );
  }

  /// Lines the divider up with the text, not with the icon.
  static const double _dividerIndent = 56;
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
    this.tone = CommyTone.neutral,
    super.key,
  });

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

  /// Colours the title, for rows that carry a status.
  final CommyTone tone;

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
        child: Row(
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
                      style: (isMonospaceSubtitle ? type.monoSmall : type.caption)
                          .copyWith(color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (valueText != null) ...<Widget>[
              SizedBox(width: spacing.s3),
              Text(
                valueText,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
            if (control != null) ...<Widget>[
              SizedBox(width: spacing.s3),
              control,
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
        ),
      ),
    );

    if (onTap == null) {
      return row;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
