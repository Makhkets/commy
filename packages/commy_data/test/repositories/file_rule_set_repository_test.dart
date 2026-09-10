import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/stub_http_adapter.dart';

/// Exception E-2, on a real directory and a stubbed socket.
///
/// The file is the record here — the core reads these by path, out of process
/// — so every assertion checks the directory rather than a returned object.
void main() {
  final source = Uri.parse('https://mirror.example/geosite-ru.srs');

  /// Something long enough to pass the "this is not an error page" floor.
  List<int> ruleSetBytes([int length = 512]) =>
      List<int>.generate(length, (index) => index % 256);

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('commy-rule-sets');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  FileRuleSetRepository repositoryOn(StubHttpAdapter adapter) {
    final repository = FileRuleSetRepository(
      client: CommyHttpClient(directClient: Dio()..httpClientAdapter = adapter),
      directoryOverride: root,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  File fileFor(String tag) => File(
        p.join(root.path, FileRuleSetRepository.directoryName, '$tag.srs'),
      );

  test('the directory is created and is the one the config will name',
      () async {
    final repository = repositoryOn(StubHttpAdapter.bytes(ruleSetBytes()));

    final directory = await repository.directory();

    expect(directory.valueOrNull, isNotNull);
    expect(Directory(directory.valueOrNull!).existsSync(), isTrue);
    expect(
      p.basename(directory.valueOrNull!),
      FileRuleSetRepository.directoryName,
    );
  });

  test('a download writes the file and reports it', () async {
    final adapter = StubHttpAdapter.bytes(ruleSetBytes());
    final repository = repositoryOn(adapter);

    final result = await repository.download(tag: 'geosite-ru', from: source);

    expect(adapter.requests.single.uri, source);
    expect(fileFor('geosite-ru').existsSync(), isTrue);
    expect(fileFor('geosite-ru').lengthSync(), 512);
    expect(result.valueOrNull?.tag, 'geosite-ru');
    expect(result.valueOrNull?.sizeBytes, 512);
  });

  test('nothing is left half written when the transfer dies', () async {
    final repository = repositoryOn(
      StubHttpAdapter.failing(DioExceptionType.connectionError),
    );

    final result = await repository.download(tag: 'geosite-ru', from: source);

    expect(result.isOk, isFalse);
    expect(fileFor('geosite-ru').existsSync(), isFalse);
    // Not even the scratch file: a `.part` left behind would be picked up by
    // nothing and cleaned up by nobody.
    expect(File('${fileFor('geosite-ru').path}.part').existsSync(), isFalse);
  });

  test('an error page served with a 200 is refused, not stored', () async {
    // A mirror answering "not found" as a body is the realistic failure, and
    // writing it under a .srs name produces a core that will not start.
    final repository = repositoryOn(StubHttpAdapter.bytes(<int>[1, 2, 3]));

    final result = await repository.download(tag: 'geosite-ru', from: source);

    expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    expect(fileFor('geosite-ru').existsSync(), isFalse);
  });

  test('listing reads size and age off the file system', () async {
    final repository = repositoryOn(StubHttpAdapter.bytes(ruleSetBytes(64)));
    await repository.download(tag: 'geoip-private', from: source);

    final sets = await repository.list();

    expect(sets.valueOrNull, hasLength(1));
    expect(sets.valueOrNull!.single.tag, 'geoip-private');
    expect(sets.valueOrNull!.single.sizeBytes, 64);
    expect(
      sets.valueOrNull!.single.updatedAt.isAfter(
        DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      isTrue,
    );
  });

  test('anything that is not a .srs is not a rule set', () async {
    final repository = repositoryOn(StubHttpAdapter.bytes(ruleSetBytes()));
    await repository.directory();
    File(p.join(root.path, FileRuleSetRepository.directoryName, 'notes.txt'))
        .writeAsStringSync('hello');

    expect((await repository.list()).valueOrNull, isEmpty);
  });

  test('deleting removes the file and is quiet about one that is gone',
      () async {
    final repository = repositoryOn(StubHttpAdapter.bytes(ruleSetBytes()));
    await repository.download(tag: 'geosite-ru', from: source);

    expect((await repository.delete('geosite-ru')).isOk, isTrue);
    expect(fileFor('geosite-ru').existsSync(), isFalse);
    expect((await repository.delete('geosite-ru')).isOk, isTrue);
  });

  test('the stream replays what is on disk and follows every write', () async {
    final repository = repositoryOn(StubHttpAdapter.bytes(ruleSetBytes()));
    final seen = <List<RuleSet>>[];
    final subscription = repository.watch().listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repository.download(tag: 'geosite-ru', from: source);
    await pumpEventQueue();

    expect(seen.first, isEmpty);
    expect(seen.last.single.tag, 'geosite-ru');
  });
}
