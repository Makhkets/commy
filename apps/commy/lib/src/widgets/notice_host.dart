import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the one-line results the tunnel produces, wherever the user is.
///
/// `TunnelController` stores a handful of them — the reachability probe
/// passed, with or without the exit address; the probe failed; the IP check
/// did not answer; the outbound was switched; a changed configuration was
/// applied — and before this existed each one was written to state and read
/// by nobody: pressing «Проверить» ran a real probe through the core and then
/// said nothing at all.
///
/// It sits in `MaterialApp.builder` rather than on the home screen because a
/// node switch can be triggered from anywhere the list is shown, and a result
/// that only appears on one route is a result the user misses.
class NoticeHost extends ConsumerStatefulWidget {
  /// Wraps [child].
  const NoticeHost({required this.child, super.key});

  /// The navigator below.
  final Widget child;

  @override
  ConsumerState<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends ConsumerState<NoticeHost> {
  @override
  Widget build(BuildContext context) {
    ref.listen<TunnelActionState>(tunnelControllerProvider, (previous, next) {
      final notice = next.notice;
      if (notice == null || notice == previous?.notice) {
        return;
      }
      _show(notice);
    });
    return widget.child;
  }

  void _show(TunnelNotice notice) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    final t = Translations.of(context);
    final ms = notice.milliseconds ?? 0;
    final ip = notice.name;
    final (String message, CommyTone tone, IconData icon) =
        switch (notice.kind) {
      TunnelNoticeKind.checkPassed => (
          ip == null
              ? t.home.checkOk(ms: ms)
              : t.home.checkOkWithIp(ms: ms, ip: ip),
          CommyTone.connected,
          CommyIcons.success,
        ),
      TunnelNoticeKind.checkFailed => (
          t.home.checkFailed,
          CommyTone.error,
          CommyIcons.warning,
        ),
      TunnelNoticeKind.switched => (
          t.home.switched(name: notice.name ?? ''),
          CommyTone.info,
          CommyIcons.proxy,
        ),
      TunnelNoticeKind.reloaded => (
          t.home.settingsApplied,
          CommyTone.info,
          CommyIcons.refresh,
        ),
      TunnelNoticeKind.ipCheckFailed => (
          t.home.ipCheckFailed(ms: ms),
          CommyTone.error,
          CommyIcons.warning,
        ),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // The toast draws its own surface, border and shadow from the
          // tokens, so the SnackBar underneath has to contribute nothing
          // (rule R4: no colour or padding decided here).
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          duration: _duration,
          content: Toast(message: message, tone: tone, icon: icon),
        ),
      );
    ref.read(tunnelControllerProvider.notifier).clearNotice();
  }

  /// Long enough to read a latency, short enough not to sit over the list.
  static const Duration _duration = Duration(seconds: 3);
}
