import 'dart:async';

import 'package:commy_data/src/util/share_latest.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stream the node list is watched through.
///
/// What matters is how often the source is opened: every opening is a drift
/// watch with a keystore read mapped on top of it.
void main() {
  late List<StreamController<int>> opened;
  late Stream<int> shared;

  setUp(() {
    opened = <StreamController<int>>[];
    shared = shareLatest(() {
      final source = StreamController<int>();
      opened.add(source);
      return source.stream;
    });
  });

  test('two listeners share one source', () async {
    final first = <int>[];
    final second = <int>[];
    final a = shared.listen(first.add);
    final b = shared.listen(second.add);
    addTearDown(a.cancel);
    addTearDown(b.cancel);

    opened.single.add(1);
    await pumpEventQueue();

    expect(opened, hasLength(1));
    expect(first, equals(<int>[1]));
    expect(second, equals(<int>[1]));
  });

  test('a late listener gets the newest value at once', () async {
    final early = shared.listen((_) {});
    addTearDown(early.cancel);
    opened.single
      ..add(1)
      ..add(2);
    await pumpEventQueue();

    expect(await shared.first, equals(2));
    expect(opened, hasLength(1));
  });

  test('the last listener leaving closes the source', () async {
    final only = shared.listen((_) {});
    opened.single.add(1);
    await pumpEventQueue();
    await only.cancel();

    expect(opened.single.hasListener, isFalse);

    // Nothing is replayed from a source nobody kept current.
    final values = <int>[];
    final next = shared.listen(values.add);
    addTearDown(next.cancel);
    await pumpEventQueue();

    expect(opened, hasLength(2));
    expect(values, isEmpty);
  });

  test('a listener after an error opens the source again, for all', () async {
    final errors = <Object>[];
    final values = <int>[];
    final staying = shared.listen(values.add, onError: errors.add);
    addTearDown(staying.cancel);
    opened.single.addError(StateError('database closed'));
    await pumpEventQueue();
    expect(errors, hasLength(1));

    final retry = shared.listen((_) {});
    addTearDown(retry.cancel);
    opened.last.add(7);
    await pumpEventQueue();

    expect(opened, hasLength(2));
    expect(opened.first.hasListener, isFalse);
    expect(values, equals(<int>[7]));
  });

  test('the source ending ends every listener', () async {
    final done = <String>[];
    shared
      ..listen((_) {}, onDone: () => done.add('a'))
      ..listen((_) {}, onDone: () => done.add('b'));

    await opened.single.close();
    await pumpEventQueue();

    expect(done, equals(<String>['a', 'b']));
  });
}
