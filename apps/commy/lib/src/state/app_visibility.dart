import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether any of the app is on screen.
///
/// The tunnel keeps this process alive with the app in the background, and
/// with it every timer the interface started. Nothing pauses a provider for
/// that: Riverpod pauses the ones a covered route watches, not the ones the
/// screen on top watches while the whole app is hidden. So a poll that
/// exists only to keep a label current asks here, and stops asking while
/// nobody could read the label. The root widget sets it from the app's
/// lifecycle.
final appVisibleProvider =
    NotifierProvider<AppVisibility, bool>(AppVisibility.new);

/// On screen until the lifecycle says otherwise.
class AppVisibility extends Notifier<bool> {
  @override
  bool build() => true;

  /// The app went into the background, or the screen went off.
  void hide() => state = false;

  /// The app is on screen again.
  void show() => state = true;
}
