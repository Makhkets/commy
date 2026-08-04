import 'dart:async';

/// Merges the newest value of two streams into one.
///
/// `rxdart` would do this in one line, but it is not in the dependency list and
/// adding a package for eleven lines is not a trade we make (CLAUDE.md §7.2).
/// Used where one domain object is assembled from two tables — the routing
/// policy lives partly in `routing_rules` and partly in `settings`.
///
/// The result emits only once both sources have produced a value, and cancels
/// both subscriptions when the last listener goes away.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A first, B second) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? firstSubscription;
  StreamSubscription<B>? secondSubscription;
  late A latestFirst;
  late B latestSecond;
  var hasFirst = false;
  var hasSecond = false;

  void emit() {
    if (hasFirst && hasSecond) {
      controller.add(combine(latestFirst, latestSecond));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      firstSubscription = first.listen(
        (value) {
          latestFirst = value;
          hasFirst = true;
          emit();
        },
        onError: controller.addError,
      );
      secondSubscription = second.listen(
        (value) {
          latestSecond = value;
          hasSecond = true;
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await firstSubscription?.cancel();
      await secondSubscription?.cancel();
    },
  );

  return controller.stream;
}
