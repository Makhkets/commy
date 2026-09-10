import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/subscription_section.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What a running «Замерить все» looks like on the card that started it.
///
/// The controller's own behaviour is covered in
/// `test/state/measurement_controller_test.dart`; the state here is pinned so
/// the assertions are about the rendering and nothing else.
void main() {
  final t = Translations();

  /// A controller frozen at [state], so a widget can be photographed mid-run.
  MeasurementController pinned(MeasurementState state) {
    return _PinnedMeasurement(state);
  }

  Future<void> pumpCard(
    WidgetTester tester,
    MeasurementState state, {
    Subscription? subscription,
  }) async {
    final item = subscription ?? testSubscription();
    final harness = CommyTestHarness(subscriptions: <Subscription>[item]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: SubscriptionSection(
              subscription: item,
              nodes: <ProxyNode>[testNode()],
            ),
          ),
        ),
        extra: <Override>[
          measurementProvider.overrideWith(() => pinned(state)),
        ],
      ),
    );
    await settle(tester);
  }

  testWidgets('a run in progress shows how far it has got and a way out',
      (tester) async {
    await pumpCard(
      tester,
      const MeasurementState(scopeId: 'sub-1', done: 8, total: 24),
    );

    expect(find.text(t.home.measuring(done: 8, total: 24)), findsOneWidget);
    expect(find.text(t.common.cancel), findsOneWidget);
    expect(find.byType(CommySpinner), findsOneWidget);
  });

  testWidgets("another card's run does not appear on this one",
      (tester) async {
    await pumpCard(
      tester,
      const MeasurementState(scopeId: 'sub-2', done: 8, total: 24),
    );

    expect(find.text(t.home.measuring(done: 8, total: 24)), findsNothing);
    expect(find.text(t.common.cancel), findsNothing);
  });

  testWidgets('with nothing running the card is just its servers',
      (tester) async {
    await pumpCard(tester, MeasurementState.idle);

    expect(find.text(t.common.cancel), findsNothing);
    expect(find.byType(NodeTile), findsOneWidget);
  });
}

class _PinnedMeasurement extends MeasurementController {
  _PinnedMeasurement(this._state);

  final MeasurementState _state;

  @override
  MeasurementState build() => _state;
}
