import 'dart:async';
import 'dart:io';

import 'package:commy_data/src/http/commy_http_client.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Rule sets as files in a directory the core can read.
///
/// A directory, not a table. The core loads these itself, by path, out of
/// process — so the file **is** the record, and a database row alongside it
/// could only ever disagree with what is actually on disk. Size and age are
/// read off the file system for the same reason.
///
/// This is exception **E-2**, and the whole of it is [download]. Nothing else
/// here touches the network, and [download] is only ever called from a button.
class FileRuleSetRepository implements RuleSetRepository {
  /// Creates the repository.
  ///
  /// [directoryOverride] exists for tests, which hand in a temporary
  /// directory rather than asking the platform for one.
  FileRuleSetRepository({
    required CommyHttpClient client,
    Directory? directoryOverride,
  })  : _client = client,
        _directoryOverride = directoryOverride;

  /// Directory name inside the application support directory.
  ///
  /// Support, not documents: on iOS documents is user-visible and backed up
  /// to iCloud, and the same reasoning that keeps the database out of there
  /// applies here (docs/00-vision.md).
  static const String directoryName = 'rule-sets';

  /// Extension the core expects. Matches `SingBoxTags.ruleSetFileName`.
  static const String extension = '.srs';

  /// Largest file we are willing to accept as a rule set.
  ///
  /// The full geosite set is a few megabytes; anything an order of magnitude
  /// past that is a mirror serving something else — an HTML error page, a
  /// redirect landing, a tarball — and writing it to disk under a `.srs` name
  /// would only produce a core that fails to start.
  static const int maxBytes = 32 * 1024 * 1024;

  /// Shortest thing that could plausibly be a compiled rule set.
  ///
  /// A "404 not found" body is about this long, and a mirror that answers 200
  /// with one is the failure this catches.
  static const int minBytes = 16;

  final CommyHttpClient _client;
  final Directory? _directoryOverride;
  final StreamController<List<RuleSet>> _changes =
      StreamController<List<RuleSet>>.broadcast();

  /// Releases the change stream.
  Future<void> dispose() => _changes.close();

  @override
  Stream<List<RuleSet>> watch() async* {
    yield (await list()).valueOrNull ?? const <RuleSet>[];
    yield* _changes.stream;
  }

  @override
  Future<Result<List<RuleSet>, CommyFailure>> list() {
    return StorageGuard.run(() async {
      final target = await _directory();
      if (!target.existsSync()) {
        return const <RuleSet>[];
      }
      final sets = <RuleSet>[
        for (final entity in target.listSync())
          if (entity is File && p.extension(entity.path) == extension)
            RuleSet(
              tag: p.basenameWithoutExtension(entity.path),
              sizeBytes: entity.lengthSync(),
              updatedAt: entity.lastModifiedSync(),
            ),
      ]..sort((a, b) => a.tag.compareTo(b.tag));
      return sets;
    });
  }

  @override
  Future<Result<String, CommyFailure>> directory() {
    return StorageGuard.run(() async => (await _directory()).path);
  }

  @override
  Future<Result<RuleSet, CommyFailure>> download({
    required String tag,
    required Uri from,
  }) async {
    final fetched = await _client.fetchBytes(from, throughTunnel: false);
    final bytes = fetched.valueOrNull;
    final failure = fetched.failureOrNull;
    if (bytes == null) {
      return Err<RuleSet, CommyFailure>(
        failure ?? CommyFailure.configInvalid('$from answered with no body'),
      );
    }
    if (bytes.length < minBytes || bytes.length > maxBytes) {
      return Err<RuleSet, CommyFailure>(
        CommyFailure.configInvalid(
          '$from answered with ${bytes.length} bytes, which is not a rule set',
        ),
      );
    }

    final written = await StorageGuard.run(() async {
      final target = await _directory();
      // Written beside the real name and renamed into place: a download that
      // dies halfway must not leave a truncated file the core will try to
      // load on the next connect.
      final partial = File(p.join(target.path, '$tag$extension.part'))
        ..writeAsBytesSync(bytes, flush: true);
      final file = File(p.join(target.path, '$tag$extension'));
      partial.renameSync(file.path);
      return RuleSet(
        tag: tag,
        sizeBytes: file.lengthSync(),
        updatedAt: file.lastModifiedSync(),
      );
    });
    await _publish();
    return written;
  }

  @override
  Future<Result<void, CommyFailure>> delete(String tag) async {
    final result = await StorageGuard.runVoid(() async {
      final target = await _directory();
      final file = File(p.join(target.path, '$tag$extension'));
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    await _publish();
    return result;
  }

  Future<Directory> _directory() async {
    final root = _directoryOverride ?? await getApplicationSupportDirectory();
    final target = Directory(p.join(root.path, directoryName));
    if (!target.existsSync()) {
      target.createSync(recursive: true);
    }
    return target;
  }

  Future<void> _publish() async {
    if (_changes.isClosed) {
      return;
    }
    _changes.add((await list()).valueOrNull ?? const <RuleSet>[]);
  }
}
