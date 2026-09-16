import 'dart:convert';
import 'dart:io';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Importing: paste, subscription, QR, file.
///
/// One controller for all four because they end in the same two places — the
/// node repository and the same result panel — and because the failure of any
/// of them has to keep the sheet open with the input intact
/// (docs/05-ux-flows.md, scenario 1).
final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);

/// Whatever the clipboard held when the import sheet was opened.
///
/// Read once, on open, and shown before anything is pasted. Nothing polls the
/// clipboard in the background — that is a permission-shaped promise as much
/// as a privacy one.
final clipboardPreviewProvider = FutureProvider<ClipboardPreview>((ref) async {
  final result = await ref.read(clipboardProvider).read();
  final text = result.valueOrNull?.trim() ?? '';
  if (text.isEmpty) {
    return ClipboardPreview.empty;
  }
  final parser = ref.read(linkParserProvider);
  if (!parser.canParse(text)) {
    return ClipboardPreview.empty;
  }
  final parsed = parser.parse(text).valueOrNull ?? ParseOutcome.empty;
  if (!parsed.hasNodes) {
    return ClipboardPreview.empty;
  }
  return ClipboardPreview(
    text: text,
    nodeCount: parsed.nodes.length,
    protocol: parsed.nodes.first.protocol,
  );
});

/// A parseable link sitting in the clipboard.
@immutable
class ClipboardPreview {
  /// Creates the preview.
  const ClipboardPreview({
    required this.text,
    required this.nodeCount,
    this.protocol,
  });

  /// Nothing useful was in the clipboard.
  static const ClipboardPreview empty = ClipboardPreview(
    text: '',
    nodeCount: 0,
  );

  /// The raw clipboard text.
  ///
  /// It holds credentials. It is shown truncated and never logged.
  final String text;

  /// How many servers the parser found in it.
  final int nodeCount;

  /// The protocol of the first one, for the `1 ссылка vless` line.
  final Protocol? protocol;

  /// Whether there is anything worth offering.
  bool get hasContent => nodeCount > 0;

  /// A one-line, host-only rendering safe to put on screen.
  String get redacted => Redact.link(text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardPreview &&
          other.text == text &&
          other.nodeCount == nodeCount &&
          other.protocol == protocol;

  @override
  int get hashCode => Object.hash(text, nodeCount, protocol);

  @override
  String toString() => 'ClipboardPreview($nodeCount nodes)';
}

/// Where an import got to.
@immutable
class ImportState {
  /// Creates the state.
  const ImportState({this.isBusy = false, this.outcome, this.failure});

  /// Nothing has been tried.
  static const ImportState idle = ImportState();

  /// A parse or a download is running.
  final bool isBusy;

  /// What the last successful import produced.
  final ParseOutcome? outcome;

  /// What the last import failed with.
  final CommyFailure? failure;

  /// Whether the last import stored at least one server.
  bool get succeeded => (outcome?.nodes.length ?? 0) > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportState &&
          other.isBusy == isBusy &&
          other.outcome == outcome &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(isBusy, outcome, failure);

  @override
  String toString() => 'ImportState(busy: $isBusy, $outcome, $failure)';
}

/// Runs the four import paths.
class ImportController extends Notifier<ImportState> {
  /// Tag on the log lines this controller writes.
  static const String logTag = 'import';

  /// Extensions the file picker offers.
  static const List<String> configExtensions = <String>[
    'json',
    'yaml',
    'yml',
    'txt',
    'conf',
  ];

  /// The import still allowed to write its result here.
  ///
  /// A subscription download takes seconds, and the sheet that started it can
  /// be dismissed in the middle of one — by the scrim, the drag handle or the
  /// back gesture, none of which stop the request. The route's end clears the
  /// controller (`ImportSheet.present` calls [reset]), and a result landing
  /// after that clear used to write itself straight back in: a report with
  /// nothing left on screen to draw it, sitting here until the next sheet
  /// opened on it.
  ///
  /// So every import takes a ticket when it starts and [reset] burns whatever
  /// is outstanding. A result on a burnt ticket is dropped, not queued: the
  /// servers it stored are on the home screen either way, and the only thing
  /// lost is a report the user walked away from. Nothing burns a ticket while
  /// the sheet that owns it is still open, which is the other half of the
  /// rule — an import running in a sheet the user is looking at always lands.
  int _ticket = 0;

  @override
  ImportState build() {
    // A rebuild is the same event as a [reset] for anything in flight: the
    // state it was going to land on is not there any more.
    _ticket++;
    return ImportState.idle;
  }

  /// Parses [input] and stores whatever it holds.
  ///
  /// Returns the id of the first imported server so the caller can select it
  /// and connect without a second round trip through the database.
  Future<String?> importText(String input) async {
    if (input.trim().isEmpty) {
      return null;
    }
    return _importText(_begin(), input);
  }

  /// Downloads [url] and stores it as a subscription.
  ///
  /// [intervalHours] is applied **after** the use case has stored the
  /// subscription, on purpose: the panel's own `profile-update-interval`
  /// header wins when it sends one, and the user's choice only fills the gap
  /// when it does not (docs/05-ux-flows.md, scenario 3).
  Future<String?> addSubscription({
    required Uri url,
    String? name,
    bool autoUpdate = true,
    int? intervalHours,
  }) async {
    final ticket = _begin();
    final result = await ref.read(addSubscriptionUseCaseProvider)(
      url: url,
      name: name,
      autoUpdate: autoUpdate,
    );
    if (!ref.mounted) {
      // The container went away while the download was in the air. There is
      // no logger to read, no repository to write to and no state to set, and
      // reaching for any of them from here throws into a future nobody awaits.
      return null;
    }
    final failure = result.failureOrNull;
    if (failure != null) {
      ref.read(appLoggerProvider).warn(
            'subscription import failed: ${failure.code}',
            tag: logTag,
          );
      _publish(ticket, ImportState(failure: failure));
      return null;
    }
    final synced = result.valueOrNull;
    final subscription = synced?.subscription;
    if (subscription != null &&
        intervalHours != null &&
        subscription.updateIntervalHours == null) {
      // Written whether or not the sheet is still there to hear about it: the
      // subscription itself landed, and a row left on the default interval
      // would refresh on a schedule the user did not choose. Only the report
      // below belongs to the sheet.
      await ref.read(subscriptionRepositoryProvider).upsert(
            subscription.copyWith(updateIntervalHours: intervalHours),
          );
    }
    final outcome = synced?.outcome ?? ParseOutcome.empty;
    _publish(ticket, ImportState(outcome: outcome));
    return outcome.nodes.isEmpty ? null : outcome.nodes.first.id;
  }

  /// Opens a file and imports its contents.
  ///
  /// The file is read as UTF-8 with malformed bytes replaced rather than
  /// throwing: a config exported by some panel in cp1251 should produce a
  /// parse failure the user can read, not a crash.
  Future<String?> importFile() async {
    final ticket = _begin();
    try {
      // One file: `pickFile`, not `pickFiles` — since file_picker 12 the
      // latter selects several by default and returns a list.
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: configExtensions,
      );
      final path = picked?.path;
      if (path == null) {
        _publish(ticket, ImportState.idle);
        return null;
      }
      final bytes = await File(path).readAsBytes();
      // The ticket the pick started on, not a fresh one: the sheet this has to
      // report to is the one that opened the picker, and going through
      // [importText] would hand the import a ticket no dismissal had burnt.
      return _importText(
        ticket,
        const Utf8Decoder(allowMalformed: true).convert(bytes),
      );
    } on Object catch (error, stackTrace) {
      _publish(ticket, ImportState(failure: UnknownFailure(error, stackTrace)));
      return null;
    }
  }

  /// Drops the last result so the sheet opens clean next time.
  ///
  /// And burns the ticket of anything still running with it: every caller is
  /// a route that has ended or a sheet about to open, and in both cases an
  /// import in flight has lost the screen it was going to report to.
  void reset() {
    _ticket++;
    state = ImportState.idle;
  }

  /// Marks an import as started and returns the ticket that lets it report.
  int _begin() {
    state = const ImportState(isBusy: true);
    return ++_ticket;
  }

  /// Writes [next] unless the import holding [ticket] has lost its audience.
  ///
  /// Two ways to lose one, and both are checked here because this is the only
  /// place a *result* is written: [reset] burnt the ticket, so the sheet that
  /// was going to draw it is gone; or the container went with it, where the
  /// write throws rather than landing.
  void _publish(int ticket, ImportState next) {
    if (ticket != _ticket || !ref.mounted) {
      return;
    }
    state = next;
  }

  Future<String?> _importText(int ticket, String input) async {
    final result = await ref.read(importLinksUseCaseProvider)(input);
    if (!ref.mounted) {
      // Nothing left to read the logger out of, let alone to report to.
      return null;
    }
    return _finish(ticket, result);
  }

  String? _finish(int ticket, Result<ParseOutcome, CommyFailure> result) {
    final failure = result.failureOrNull;
    if (failure != null) {
      // Logged even when the report is dropped: the import did fail, and the
      // log is the one record of it the diagnostics screen can still show.
      ref.read(appLoggerProvider).warn(
            'import failed: ${failure.code}',
            tag: logTag,
          );
      _publish(ticket, ImportState(failure: failure));
      return null;
    }
    // What the use case returns is what the repository holds, not what the
    // parser counted: two links naming the same server are one row, and the
    // panel reads `outcome.nodes.length` straight off this state. An import
    // is reported once and there is no history to correct an over-count in.
    final outcome = result.valueOrNull ?? ParseOutcome.empty;
    _publish(ticket, ImportState(outcome: outcome));
    return outcome.nodes.isEmpty ? null : outcome.nodes.first.id;
  }
}
