import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything above the server list: metrics, the button, the chosen server.
///
/// The order is fixed by docs/design-refs/02-home-idle.png and
/// 03-home-connected.png — metrics strip, connect button, selected server,
/// and, only while the tunnel is up, the check button left-aligned above the
/// list. The check button appears rather than being disabled: there is nothing
/// to check when there is no tunnel, and a permanently greyed control teaches
/// people to ignore it.
class HeroArea extends ConsumerWidget {
  /// Creates the area.
  const HeroArea({required this.onChooseNode, super.key});

  /// Opens the server picker, or `null` when there is no picker to open.
  ///
  /// `null` is the two-pane case: the list is the pane on the other side of
  /// the seam, permanently on screen, so `SelectedNode` drops its chevron
  /// rather than promise a list that is already there.
  final VoidCallback? onChooseNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final status = ref.watch(tunnelStatusProvider);
    final connectState = ConnectState.of(status);
    // On Auto the chip names the group and the server the group landed on,
    // in that order: "Авто" alone would leave the one question this row
    // exists to answer — through what? — unanswered for as long as the core
    // keeps choosing.
    final isAuto = ref.watch(autoSelectedProvider);
    final node =
        isAuto ? ref.watch(autoNodeProvider) : ref.watch(selectedNodeProvider);
    final traffic = ref.watch(trafficProvider).value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.s4,
            vertical: spacing.s3,
          ),
          child: MetricsStrip(
            uplink: traffic?.uplink ?? 0,
            downlink: traffic?.downlink ?? 0,
            session: _sessionOf(status, now),
            isActive: connectState.isTunnelUp,
            uplinkLabel: t.metrics.up,
            sessionLabel: t.metrics.session,
            downlinkLabel: t.metrics.down,
          ),
        ),
        SizedBox(height: spacing.s4),
        Center(
          child: ConnectButton(
            state: connectState,
            semanticLabel: t.a11y.connect,
            semanticValue: _statusLabel(connectState, t),
            onPressed: () => _toggle(ref),
          ),
        ),
        SizedBox(height: spacing.s5),
        SelectedNode(
          name: _nodeLabel(t, isAuto: isAuto, node: node),
          semanticLabel: t.home.selectNode,
          flag: node == null
              ? null
              : CountryFlag(
                  countryCode: node.countryCode,
                  semanticLabel: node.countryCode == null
                      ? null
                      : t.a11y.flag(country: node.countryCode!),
                ),
          onTap: onChooseNode,
        ),
        if (connectState.showsCheckButton) ...<Widget>[
          SizedBox(height: spacing.s4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: CheckButton(
              label: t.connect.check,
              isChecking: status is TunnelChecking,
              onPressed: () => _check(ref),
            ),
          ),
        ],
        SizedBox(height: spacing.s4),
      ],
    );
  }

  /// What the chip reads: the group, the group and its pick, or the server.
  String _nodeLabel(
    Translations t, {
    required bool isAuto,
    required ProxyNode? node,
  }) {
    if (!isAuto) {
      return node?.name ?? t.home.noNodeSelected;
    }
    if (node == null) {
      return t.home.auto;
    }
    return '${t.home.auto}${NodeTile.descriptorSeparator}${node.name}';
  }

  void _toggle(WidgetRef ref) {
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

  String _statusLabel(ConnectState state, Translations t) => switch (state) {
        ConnectState.idle => t.connect.idle,
        ConnectState.starting => t.connect.starting,
        ConnectState.checking => t.connect.checking,
        ConnectState.connected => t.connect.connected,
        ConnectState.stopping => t.connect.stopping,
        ConnectState.error => t.connect.error,
      };
}
