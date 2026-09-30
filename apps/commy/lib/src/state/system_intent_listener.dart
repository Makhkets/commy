/// Consumes `dev.commy.app/intents`, the channel Kotlin fills and Dart ignored.
///
/// The manifest registers Commy as a handler for `vless://`, `vmess://`,
/// `trojan://`, `ss://`, `hysteria2://`, `tuic://`, for JSON and YAML config
/// files, and for shared text. All of that arrives here. Until this existed the
/// app appeared in "Open with", opened on the tap, and did nothing whatsoever —
/// which is a worse first contact than not registering at all.
library;

import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/state/unreadable_file_notice.dart';
import 'package:commy_core/commy_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tag the log lines from this file carry.
const String _tag = 'intents';

/// The last link or text handed to the app from outside, waiting to be shown.
///
/// Held rather than acted on: an import that happens without the user seeing
/// what is being imported is exactly the surprise docs/05-ux-flows.md avoids
/// when it insists the clipboard is shown before it is pasted. The home screen
/// watches this and opens the import sheet with the text already in it.
final pendingImportProvider =
    NotifierProvider<PendingImport, String?>(PendingImport.new);

/// Holds one pending payload.
class PendingImport extends Notifier<String?> {
  @override
  String? build() => null;

  /// Offers [payload] to whichever screen is watching.
  // ignore: use_setters_to_change_properties
  void offer(String payload) => state = payload;

  /// Drops it once the sheet has taken it.
  void take() => state = null;
}

/// Subscribes to the channel for as long as the app is alive.
///
/// Watched from the root, like the log pump: a deep link that arrives while
/// the user is three screens deep still has to be honoured.
final systemIntentProvider = Provider<void>((ref) {
  final logger = ref.watch(appLoggerProvider);
  final subscription = ref.watch(systemIntentsProvider).events.listen(
    (intent) {
      // Never log `intent.payload`: a vless:// link carries the user's UUID
      // and this line would follow it into a bug report (rule R3).
      logger.info('system intent: ${intent.kind.wireName}', tag: _tag);
      switch (intent.kind) {
        case SystemIntentKind.link:
        case SystemIntentKind.text:
          final payload = intent.payload;
          if (payload != null) {
            ref.read(pendingImportProvider.notifier).offer(payload);
          }
        case SystemIntentKind.file:
          // A file the platform could read came in as `text` above, its
          // contents in place of a shared line. This one it could not open,
          // and the app has just come to the front for it: said on screen,
          // not only here.
          logger.warn('a file handed to the app could not be read', tag: _tag);
          ref.read(unreadableFileProvider.notifier).raise();
        case SystemIntentKind.connect:
          unawaited(ref.read(tunnelControllerProvider.notifier).connect());
      }
    },
    onError: (Object error) => logger.warn('intent stream: $error', tag: _tag),
  );
  ref.onDispose(subscription.cancel);
});

/// The platform source of intents.
///
/// Overridable so a test can push events without a device, and so the desktop
/// composition root can hand over a source that never emits.
final systemIntentsProvider = Provider<SystemIntents>((ref) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return const _NoIntents();
  }
  return const SystemIntents();
});

/// A source for the platforms that have no such thing.
class _NoIntents implements SystemIntents {
  const _NoIntents();

  @override
  Stream<SystemIntent> get events => const Stream<SystemIntent>.empty();
}
