import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/node_picker_sheet.dart';
import 'package:commy/src/state/access_check.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/node_descriptors.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything above the server list: the answer, the route, the one button.
///
/// docs/04-design-system.md §8 and §9. The screen opens with the answer to
/// the question it exists for — "Connected", "Not connected" — in the largest
/// type in the product, and under it the line of fact that goes with it: the
/// session clock and the rates while the tunnel is up, where traffic goes
/// while it is not. Then the route, the signature: this device, the server,
/// the internet, each leg dashed, travelling or solid. The server's stop is
/// the server picker and the internet's stop carries the access check —
/// each control beside what it acts on. Last, the one action of the screen,
/// the full width of the column: "Connect" or "Disconnect", in words.
///
/// The picker opens at every width; it loses its chevron only when there is
/// nothing to pick between.
class HeroArea extends ConsumerWidget {
  /// Creates the area.
  const HeroArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;
    final type = context.typography;
    final status = ref.watch(tunnelStatusProvider);
    final action = ref.watch(tunnelControllerProvider);
    final access = ref.watch(accessCheckProvider);
    final connectState = ConnectState.of(status);
    // On Auto the stop names the server the group landed on, and says that
    // the group chose it: "Auto" alone would leave the question this stop
    // exists to answer — through what? — unanswered.
    final isAuto = ref.watch(autoSelectedProvider);
    final node =
        isAuto ? ref.watch(autoNodeProvider) : ref.watch(selectedNodeProvider);
    // The flag a panel typed into the name goes into the flag slot, exactly
    // as in the list below.
    final label = node == null ? null : NodeLabel.of(node);
    final nodes = ref.watch(nodesProvider).value ?? const <ProxyNode>[];
    final hasChoice = NodePickerSheet.isOffered(nodes);
    final traffic = ref.watch(trafficProvider).value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final isChecking = status is TunnelChecking || action.isChecking;
    final checkFailed = access != null && !access.passed;

    final serverName = node == null
        ? (isAuto ? t.home.auto : t.home.noNodeSelected)
        : label!.text;
    final tags = <NodeTag>[
      if (isAuto)
        NodeTag(node == null ? t.route.autoWaiting : t.route.autoPicked),
      if (!isAuto && node != null) ...NodeDescriptors.of(node),
    ];
    final flag = node == null
        ? (isAuto
            ? const CountryFlag(countryCode: CountryFlag.europeanUnion)
            : null)
        : CountryFlag(
            countryCode: label!.countryCode,
            semanticLabel: label.countryCode == null
                ? null
                : t.a11y.flag(country: label.countryCode!),
          );

    final String? internetStatus;
    final CommyTone internetTone;
    if (isChecking) {
      internetStatus = t.route.checking;
      internetTone = CommyTone.neutral;
    } else if (connectState == ConnectState.connected && access != null) {
      internetStatus = access.passed
          ? t.route.online(ms: access.milliseconds ?? 0)
          : t.route.noAnswer;
      internetTone = access.passed ? CommyTone.connected : CommyTone.connecting;
    } else {
      internetStatus = null;
      internetTone = CommyTone.neutral;
    }

    final failure = switch (status) {
      TunnelError(:final failure) => failure,
      _ => null,
    };
    final breakAt = failure != null
        ? _breakOf(failure)
        : checkFailed && connectState == ConnectState.connected
            ? RouteBreak.internet
            : null;

    final answer = _answer(connectState, t);
    final tunnelUp = connectState.isTunnelUp;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.s4,
            spacing.s2,
            spacing.s4,
            spacing.s0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The words the route says, as the heading of the screen: a
              // screen reader hears them once, here, and the route's own
              // summary below carries the path.
              Semantics(
                container: true,
                header: true,
                liveRegion: true,
                // Swapped, not cross-faded: during a fade the outgoing words
                // stayed in the tree beside the new ones, and the live
                // region could announce both.
                child: Text(
                  answer,
                  style: type.display.copyWith(color: colors.textPrimary),
                ),
              ),
              SizedBox(height: spacing.s1),
              if (tunnelUp)
                MetricsStrip(
                  uplink: traffic?.uplink ?? 0,
                  downlink: traffic?.downlink ?? 0,
                  session: _sessionOf(status, now),
                  isActive: true,
                  uplinkLabel: t.metrics.up,
                  sessionLabel: t.metrics.session,
                  downlinkLabel: t.metrics.down,
                )
              else
                Semantics(
                  container: true,
                  child: Text(
                    _hint(connectState, t, hasServers: nodes.isNotEmpty),
                    style: type.body.copyWith(color: colors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.s6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.s4),
          child: ConnectionRoute(
            semanticLabel: t.route.summary(
              device: t.route.device,
              server: serverName,
              internet: internetStatus == null
                  ? t.route.internet
                  : '${t.route.internet}: $internetStatus',
              state: answer,
            ),
            state: connectState,
            deviceLabel: t.route.device,
            serverName: serverName,
            internetLabel: t.route.internet,
            flag: flag,
            tags: tags,
            latency: node?.latency,
            onServerTap: hasChoice
                ? () => unawaited(NodePickerSheet.show(context))
                : null,
            serverSemanticLabel: t.home.selectNode,
            internetStatus: internetStatus,
            internetTone: internetTone,
            checkLabel: t.route.check,
            onCheck: tunnelUp ? () => _check(ref) : null,
            isChecking: isChecking,
            breakAt: breakAt,
          ),
        ),
        SizedBox(height: spacing.s5),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.s4),
          child: _MainAction(
            state: connectState,
            onPressed: () => _toggle(ref),
          ),
        ),
        SizedBox(height: spacing.s6),
      ],
    );
  }

  /// Where the route broke, by what broke it.
  ///
  /// The device: the VPN permission was refused, or the helper that owns the
  /// tunnel on a desktop is not there. Everything else that keeps a tunnel
  /// from coming up — a configuration, a protocol, the core — happened on the
  /// way to the server.
  static RouteBreak _breakOf(CommyFailure failure) => switch (failure) {
        PermissionDeniedFailure() ||
        HelperUnavailableFailure() =>
          RouteBreak.device,
        _ => RouteBreak.server,
      };

  void _toggle(WidgetRef ref) {
    // The one tap that matters most gets the lightest tick, on the same
    // frame the button sinks: cause and feel together (docs/04 §7).
    unawaited(HapticFeedback.lightImpact());
    unawaited(ref.read(tunnelControllerProvider.notifier).toggle());
  }

  void _check(WidgetRef ref) {
    // The button is the one place exception E-1 may fire from
    // (docs/09-security-privacy.md); the automatic probe after a connect
    // calls `check()` without the flag.
    unawaited(
      ref.read(tunnelControllerProvider.notifier).check(includeIp: true),
    );
  }

  /// How long the tunnel has been up, or zero when it is not.
  Duration _sessionOf(TunnelStatus status, DateTime now) => switch (status) {
        TunnelConnected(:final since) => now.difference(since),
        TunnelChecking(:final since) => now.difference(since),
        TunnelIdle() ||
        TunnelStarting() ||
        TunnelStopping() ||
        TunnelError() =>
          Duration.zero,
      };

  /// The answer: what the route says, in words.
  ///
  /// A tunnel being checked is already "Connected" — the route's last leg
  /// says the check is still running — so the heading does not flicker
  /// between two words the moment the probe comes back.
  static String _answer(ConnectState state, Translations t) => switch (state) {
        ConnectState.idle => t.route.idle,
        ConnectState.starting => t.route.starting,
        ConnectState.checking || ConnectState.connected => t.route.connected,
        ConnectState.stopping => t.route.stopping,
        ConnectState.error => t.route.error,
      };

  /// The line under the answer while the tunnel is down: where traffic goes
  /// now, or what is happening. A failure explains itself in the banner
  /// under the button, so the line stays quiet then.
  static String _hint(
    ConnectState state,
    Translations t, {
    required bool hasServers,
  }) =>
      switch (state) {
        ConnectState.idle =>
          hasServers ? t.route.idleHint : t.connect.noServers,
        ConnectState.starting => t.route.startingHint,
        ConnectState.error => t.route.idleHint,
        ConnectState.stopping => t.route.idleHint,
        ConnectState.checking || ConnectState.connected => '',
      };
}

/// The one action of the screen: "Connect" or "Disconnect", in words.
///
/// The verb names the result (docs/04 §12). Primary — the action fill — while
/// it starts a connection; tinted while it ends one or calls one off, so the
/// screen's loudest control is always the way *in*. Disconnecting shows a
/// spinner and takes no tap until the core has let go.
class _MainAction extends StatelessWidget {
  const _MainAction({required this.state, required this.onPressed});

  final ConnectState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final (label, variant, icon, busy) = switch (state) {
      ConnectState.idle || ConnectState.error => (
          t.route.connect,
          CommyButtonVariant.primary,
          CommyIcons.power,
          false,
        ),
      ConnectState.starting => (
          t.route.cancel,
          CommyButtonVariant.secondary,
          CommyIcons.close,
          false,
        ),
      ConnectState.checking || ConnectState.connected => (
          t.route.disconnect,
          CommyButtonVariant.secondary,
          CommyIcons.power,
          false,
        ),
      ConnectState.stopping => (
          t.route.stopping,
          CommyButtonVariant.secondary,
          null,
          true,
        ),
    };
    return CommyButton(
      label: label,
      icon: icon,
      variant: variant,
      isLarge: true,
      isFullWidth: true,
      isLoading: busy,
      onPressed: onPressed,
    );
  }
}
