import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/system_intent_listener.dart';
import 'package:commy/src/widgets/notice_host.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What the app does with the things Android hands it from outside.
///
/// A config file opened with Commy in a file manager or a chat is read on the
/// platform side and arrives as its text. One that could not be read arrives
/// as a `file`, and that used to be a warning in the log: the app came to the
/// front on the tap and did nothing whatsoever.
void main() {
  final t = Translations();

  late CommyTestHarness harness;
  late StreamController<SystemIntent> intents;

  setUp(() {
    harness = CommyTestHarness();
    intents = StreamController<SystemIntent>.broadcast();
  });

  tearDown(() async {
    await intents.close();
    await harness.dispose();
  });

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      harness.wrap(
        const NoticeHost(child: _Listening()),
        extra: <Override>[
          systemIntentsProvider.overrideWithValue(_Intents(intents.stream)),
        ],
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(_Listening)),
      listen: false,
    );
  }

  testWidgets('a file that could not be read says so', (tester) async {
    await pumpApp(tester);

    intents.add(const SystemIntent(kind: SystemIntentKind.file));
    await settle(tester);

    final toast = tester.widget<Toast>(find.byType(Toast));
    expect(toast.message, t.import.file.unreadable);
    expect(toast.tone, CommyTone.error);

    await tester.pump(ToastMessenger.duration);
    await tester.pumpAndSettle();
  });

  testWidgets('a file that was read is offered like shared text',
      (tester) async {
    final container = await pumpApp(tester);
    const contents = 'vless://11111111-2222-3333-4444-555555555555'
        '@nl-03.example.net:443#NL';

    intents
        .add(const SystemIntent(kind: SystemIntentKind.text, text: contents));
    await settle(tester);

    expect(container.read(pendingImportProvider), contents);
    expect(find.byType(Toast), findsNothing);
  });
}

/// Stands in for the app root, which keeps the intent listener alive.
class _Listening extends ConsumerWidget {
  const _Listening();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(systemIntentProvider);
    return const SizedBox.expand();
  }
}

/// Intents pushed by the test instead of the platform channel.
class _Intents implements SystemIntents {
  const _Intents(this.events);

  @override
  final Stream<SystemIntent> events;
}
