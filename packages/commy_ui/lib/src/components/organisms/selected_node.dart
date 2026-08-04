import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// What is selected, sitting under the connect button: flag, name, chevron.
///
/// Tapping it opens the node list. It is deliberately quiet — no card, no
/// border, no fill — because the button above it is the thing being looked
/// at; this row only answers "through what?".
///
/// [flag] is passed in rather than built here so that this component never
/// has to know about countries. Screens hand it a `CountryFlag`; when there
/// is nothing to show, the row is just name and chevron.
class SelectedNode extends StatelessWidget {
  /// Creates the selected-node row.
  ///
  /// [name] is what the user reads and is already whatever the node is
  /// called. [onTap] of `null` means there is nothing to choose from — the
  /// chevron then disappears, so the row does not promise a list that will
  /// not open.
  const SelectedNode({
    required this.name,
    required this.onTap,
    this.flag,
    this.semanticLabel,
    super.key,
  });

  /// Name of the selected node.
  final String name;

  /// Opens the node list. `null` when there is nothing to open.
  final VoidCallback? onTap;

  /// Flag of the node's country, 26×20. Usually a `CountryFlag`.
  final Widget? flag;

  /// Overrides the label announced to assistive technology.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;

    return Center(
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: semanticLabel,
        child: Material(
          color: CommyColors.transparent,
          borderRadius: radii.fullAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radii.fullAll,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: CommySizes.minTapTarget,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (flag != null) ...<Widget>[
                      flag!,
                      SizedBox(width: spacing.s3),
                    ],
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.title3.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (onTap != null) ...<Widget>[
                      SizedBox(width: spacing.s1),
                      Icon(
                        CommyIcons.chevronDown,
                        size: CommySizes.iconControl,
                        color: colors.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
