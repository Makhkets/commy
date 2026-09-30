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
///
/// A paused listener is sent nothing, and gets the newest value when it
/// resumes: every value is the whole list, so the ones in between are worth
/// nothing, and Riverpod pauses a provider's subscription whenever no screen
/// watches it. While every listener is paused the source is paused too — a
/// drift watch then stops re-running its query and runs it once on resume,
/// which is what each provider's own watch did before they shared one.
Stream<T> shareLatest<T>(Stream<T> Function() open) {
  final listeners = <MultiStreamController<T>>[];
  // Paused listeners, and whether each has missed a value since it paused.
  final paused = <MultiStreamController<T>, bool>{};
  StreamSubscription<T>? source;
  var sourcePaused = false;
  // A record, so a nullable `T` that happens to be null still counts as a
  // value.
  (T,)? latest;
  var failed = false;

  void reset() {
    source = null;
    sourcePaused = false;
    latest = null;
    failed = false;
  }

  // Pauses the source while nobody can take a value, resumes it otherwise.
  void settle() {
    final idle = listeners.isNotEmpty && paused.length == listeners.length;
    final running = source;
    if (running == null || idle == sourcePaused) {
      return;
    }
    sourcePaused = idle;
    if (idle) {
      running.pause();
    } else {
      running.resume();
    }
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
          if (paused.containsKey(each)) {
            paused[each] = true;
          } else {
            each.add(value);
          }
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
        paused.clear();
        reset();
        for (final each in closing) {
          unawaited(each.close());
        }
      },
    );
    settle();
    listener
      ..onPause = () {
        paused[listener] = false;
        settle();
      }
      ..onResume = () {
        final missed = paused.remove(listener) ?? false;
        final newest = latest;
        if (missed && newest != null) {
          listener.add(newest.$1);
        }
        settle();
      }
      ..onCancel = () {
        listeners.remove(listener);
        paused.remove(listener);
        if (listeners.isNotEmpty) {
          settle();
          return null;
        }
        final cancelled = source?.cancel();
        reset();
        return cancelled;
      };
  });
}
