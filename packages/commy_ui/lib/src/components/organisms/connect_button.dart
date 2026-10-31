import 'package:commy_ui/src/components/atoms/commy_spinner.dart';
import 'package:commy_ui/src/components/commy_focusable.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/commy_pressable.dart';
import 'package:commy_ui/src/components/organisms/connect_state.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The main connection control: a large, tactile dial and a visible verb.
///
/// The ring expresses tunnel state; the route below explains reachability.
/// Starting remains cancellable. Stopping alone locks the control until the
/// core has released the tunnel. Labels come from the application's locale.
class ConnectButton extends StatefulWidget {
  /// Creates the connection dial.
  const ConnectButton({
    required this.state,
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// The state shown by the ring and central symbol.
  final ConnectState state;

  /// The translated action, shown below the dial without truncation.
  final String label;

  /// Connects, disconnects or cancels. Null disables the control.
  final VoidCallback? onPressed;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final motion = context.motion;
    final enabled =
        widget.onPressed != null && widget.state != ConnectState.stopping;
    final activate = enabled ? widget.onPressed : null;
    final busy = widget.state.isTransitional;
    final ink = !enabled
        ? colors.textDisabled
        : switch (widget.state) {
            ConnectState.connected ||
            ConnectState.checking =>
              colors.statusConnected,
            ConnectState.starting => colors.statusConnecting,
            ConnectState.error => colors.statusError,
            _ => colors.textPrimary,
          };
    final ring = switch (widget.state) {
      ConnectState.connected ||
      ConnectState.checking =>
        colors.statusConnectedSolid,
      ConnectState.starting => colors.statusConnectingSolid,
      ConnectState.error => colors.statusErrorSolid,
      _ => colors.borderStrong,
    };
    final surface = _hovered && enabled ? colors.bgOverlay : colors.bgSurface;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: activate,
      excludeSemantics: true,
      child: CommyFocusable(
        onActivate: activate,
        builder: (context, {required isFocused}) => MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: CommyPressable(
            enabled: enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: activate,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: CommySizes.connectDiameter,
                    height: CommySizes.connectDiameter,
                    padding: EdgeInsets.all(spacing.s1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: CommyFocusable.ring(
                        colors,
                        isFocused: isFocused,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedContainer(
                          duration: motion.fast,
                          curve: motion.fastCurve,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[surface, colors.bgOverlay],
                            ),
                            border: Border.all(
                              color: busy ? colors.borderSubtle : ring,
                              width: CommySizes.borderThick,
                            ),
                          ),
                          child: Icon(
                            widget.state == ConnectState.starting
                                ? CommyIcons.close
                                : CommyIcons.power,
                            size: CommySizes.connectIcon,
                            color: ink,
                          ),
                        ),
                        if (busy)
                          IgnorePointer(
                            child: CommySpinner(color: ring),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.s2),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: context.typography.bodyStrong.copyWith(
                      color:
                          enabled ? colors.textPrimary : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
