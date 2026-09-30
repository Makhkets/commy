import 'dart:async';

/// One subscription to [open]'s stream, shared by every listener, with the
/// newest value handed to whoever joins late.
///
/// Drift shares a watched query between listeners, but whatever is mapped on
/// top of it runs once per listener. For the node list that is a keystore
/// `readAll` and a JSON decode of every server's secrets on every write: two
/// providers watching it paid twice, and "measure all" writes once per server.
/// `rxdart` has this as `shareValue`; a package for forty lines is not a trade
/// we make (CLAUDE.md §7.2).
///
/// The source is opened by the first listener and cancelled with the last, so
/// nothing is watched while nobody looks; the value it last produced goes with
/// it, since it stops being kept current. An error is not replayed: whoever
/// joins after one is asking again — a retry button does exactly that — so the
/// source is opened afresh, for every listener, instead.
Stream<T> shareLatest<T>(Stream<T> Function() open) {
  final listeners = <MultiStreamController<T>>[];
  StreamSubscription<T>? source;
  // A record, so a nullable `T` that happens to be null still counts as a
  // value.
  (T,)? latest;
  var failed = false;

  void reset() {
    source = null;
    latest = null;
    failed = false;
  }

  return Stream<T>.multi((listener) {
    listeners.add(listener);
    if (failed) {
      unawaited(source?.cancel());
      reset();
    }
    final replay = latest;
    if (replay != null) {
      listener.add(replay.$1);
    }
    source ??= open().listen(
      (value) {
        latest = (value,);
        failed = false;
        for (final each in List<MultiStreamController<T>>.of(listeners)) {
          each.add(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        failed = true;
        for (final each in List<MultiStreamController<T>>.of(listeners)) {
          each.addError(error, stackTrace);
        }
      },
      onDone: () {
        final closing = List<MultiStreamController<T>>.of(listeners);
        listeners.clear();
        reset();
        for (final each in closing) {
          unawaited(each.close());
        }
      },
    );
    listener.onCancel = () {
      listeners.remove(listener);
      if (listeners.isNotEmpty) {
        return null;
      }
      final cancelled = source?.cancel();
      reset();
      return cancelled;
    };
  });
}
