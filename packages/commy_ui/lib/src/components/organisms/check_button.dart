import 'package:commy_ui/src/components/atoms/commy_spinner.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The "check" action: does traffic actually flow through the tunnel?
///
/// It belongs **at the leading edge of the content, above the list** — not
/// centred under the connect button. Centred, it hangs in empty space and
/// argues with the main action, so this widget aligns itself to the start and
/// the caller does not get to choose.
///
/// It is shown only while the tunnel is up, which `ConnectState` answers as
/// `showsCheckButton`: there is nothing to check before then, and a button
/// that cannot do anything is worse than no button at all.
///
/// The pill is 36 dp tall but the tap target around it is 48 — the whole
/// stadium, including the transparent margin above and below.
class CheckButton extends StatelessWidget {
  /// Creates a check button.
  ///
  /// [label] is the finished, translated word; this package owns no text.
  /// While [isChecking] the icon becomes a spinner and taps are ignored, so
  /// that a slow probe cannot be started twice.
  const CheckButton({
    required this.label,
    required this.onPressed,
    this.icon = CommyIcons.refresh,
    this.isChecking = false,
    this.semanticLabel,
    super.key,
  });

  /// Text on the button. Already translated.
  final String label;

  /// Starts the reachability probe. `null` disables the button.
  final VoidCallback? onPressed;

  /// Leading Lucide icon, replaced by a spinner while [isChecking].
  final IconData icon;

  /// Whether a probe is already running.
  final bool isChecking;

  /// Overrides the label announced to assistive technology.
  final String? semanticLabel;

  /// Whether a tap will actually do something.
  bool get isEnabled => onPressed != null && !isChecking;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final foreground = isEnabled ? colors.textPrimary : colors.textDisabled;
    // The visible pill is smaller than the tap target; the difference is
    // transparent margin that still takes taps.
    const tapMargin =
        (CommySizes.minTapTarget - CommySizes.buttonHeightSmall) / 2;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        enabled: isEnabled,
        label: semanticLabel,
        child: Material(
          color: CommyColors.transparent,
          borderRadius: radii.fullAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isEnabled ? onPressed : null,
            borderRadius: radii.fullAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: tapMargin),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.bgOverlay,
                  borderRadius: radii.fullAll,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.s4,
                    vertical: spacing.s2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (isChecking)
                        CommySpinner(
                          size: CommySizes.iconControl,
                          color: foreground,
                        )
                      else
                        Icon(
                          icon,
                          size: CommySizes.iconControl,
                          color: foreground,
                        ),
                      SizedBox(width: spacing.s2),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typography.bodyStrong.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
