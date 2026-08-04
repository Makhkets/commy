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

  @override
  ImportState build() => ImportState.idle;

  /// Parses [input] and stores whatever it holds.
  ///
  /// Returns the id of the first imported server so the caller can select it
  /// and connect without a second round trip through the database.
  Future<String?> importText(String input) async {
    if (input.trim().isEmpty) {
      return null;
    }
    state = const ImportState(isBusy: true);
    final result = await ref.read(importLinksUseCaseProvider)(input);
    return _finish(result);
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
    state = const ImportState(isBusy: true);
    final result = await ref.read(addSubscriptionUseCaseProvider)(
      url: url,
      name: name,
      autoUpdate: autoUpdate,
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      ref.read(appLoggerProvider).warn(
            'subscription import failed: ${failure.code}',
            tag: logTag,
          );
      state = ImportState(failure: failure);
      return null;
    }
    final synced = result.valueOrNull;
    final subscription = synced?.subscription;
    if (subscription != null &&
        intervalHours != null &&
        subscription.updateIntervalHours == null) {
      await ref.read(subscriptionRepositoryProvider).upsert(
            subscription.copyWith(updateIntervalHours: intervalHours),
          );
    }
    final outcome = synced?.outcome ?? ParseOutcome.empty;
    state = ImportState(outcome: outcome);
    return outcome.nodes.isEmpty ? null : outcome.nodes.first.id;
  }

  /// Opens a file and imports its contents.
  ///
  /// The file is read as UTF-8 with malformed bytes replaced rather than
  /// throwing: a config exported by some panel in cp1251 should produce a
  /// parse failure the user can read, not a crash.
  Future<String?> importFile() async {
    state = const ImportState(isBusy: true);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: configExtensions,
      );
      final files = picked?.files ?? const <PlatformFile>[];
      final path = files.isEmpty ? null : files.first.path;
      if (path == null) {
        state = ImportState.idle;
        return null;
      }
      final bytes = await File(path).readAsBytes();
      return importText(const Utf8Decoder(allowMalformed: true).convert(bytes));
    } on Object catch (error, stackTrace) {
      state = ImportState(failure: UnknownFailure(error, stackTrace));
      return null;
    }
  }

  /// Drops the last result so the sheet opens clean next time.
  void reset() => state = ImportState.idle;

  Future<String?> _finish(Result<ParseOutcome, CommyFailure> result) async {
    final failure = result.failureOrNull;
    if (failure != null) {
      ref.read(appLoggerProvider).warn(
            'import failed: ${failure.code}',
            tag: logTag,
          );
      state = ImportState(failure: failure);
      return null;
    }
    final outcome = result.valueOrNull ?? ParseOutcome.empty;
    state = ImportState(outcome: outcome);
    return outcome.nodes.isEmpty ? null : outcome.nodes.first.id;
  }
}
