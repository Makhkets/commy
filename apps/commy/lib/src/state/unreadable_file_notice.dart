import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file handed to the app that could not be read, until that is said.
///
/// A config file opened with Commy or shared to it is read on the platform
/// side as it arrives, and its text comes in the way a shared link does. What
/// arrives as a file is one that could not be opened — a provider that went
/// away, a grant that lapsed, something too big to be a config. That used to
/// be a warning in the log and nothing else, after the app had come to the
/// front for the tap. The intent listener has no screen to say it on, so it
/// writes here, and `NoticeHost` shows it and clears it — the pattern
/// `TunnelNotice` set.
final unreadableFileProvider =
    NotifierProvider<UnreadableFileNotice, bool>(UnreadableFileNotice.new);

/// Whether an unreadable file is waiting to be mentioned.
class UnreadableFileNotice extends Notifier<bool> {
  @override
  bool build() => false;

  /// Says a file arrived that could not be read.
  void raise() => state = true;

  /// Drops the notice once it has been shown.
  void clear() => state = false;
}
