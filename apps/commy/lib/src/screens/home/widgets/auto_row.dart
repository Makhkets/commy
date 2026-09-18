import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Auto, as a row you pick like any server.
///
/// docs/05-ux-flows.md says what this is: "**Auto** — не узел, а группа:
/// выбирает лучший и перепроверяет по интервалу." It is drawn with the same
/// [NodeTile] as the servers below precisely because it is chosen the same
/// way — one of them wins the active bar, never two — and it sits above the
/// subscription cards because it belongs to none of them: the group measures
/// every stored server, whichever panel it came from.
///
/// The second line and the flag follow whatever the core is currently using,
/// so this row answers "so where am I, then?" without the user opening
/// diagnostics. Until the core has said — tunnel down, or freshly up — it says
/// what the group does instead of naming a server it has not picked yet.
class AutoRow extends ConsumerWidget {
  /// Creates the row.
  const AutoRow({this.onChosen, super.key});

  /// Called once a tap has chosen Auto. The picker sheet closes itself with
  /// it; the list leaves it `null`.
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final isActive = ref.watch(autoSelectedProvider);
    final picked = isActive ? ref.watch(autoNodeProvider) : null;
    final label = picked == null ? null : NodeLabel.of(picked);

    return NodeTile(
      name: t.home.auto,
      descriptors: <String>[label?.text ?? t.home.autoSubtitle],
      latency: picked?.latency,
      countryCode: label?.countryCode,
      isActive: isActive,
      onTap: () {
        unawaited(ref.read(tunnelControllerProvider.notifier).selectAuto());
        onChosen?.call();
      },
    );
  }
}
