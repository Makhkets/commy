import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy_core/commy_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logger the app runs is `commy_data`'s `LogRedactor` in front of
/// `AppLogger` — not `commy_core`'s thinner default (rule R3).
///
/// One line in `main` and one in the provider used to say so, and nothing
/// held either. The line below carries what only the wider redactor removes:
/// a credential header written as JSON, the way an XHTTP transport's
/// `headers` reach a core log.
void main() {
  const token = 'Bearer eyJhbGciOiJIUzI1NiJ9.cdn-access.sig';
  const uuid = '11111111-2222-3333-4444-555555555555';
  const line = 'dial {"headers":{"Authorization":"$token"}} '
      'vless://$uuid@nl.example.net:443?security=reality';

  void expectScrubbed(AppLogger logger) {
    logger.info(line, tag: 'test');
    final stored = logger.buffer.single.message;
    expect(stored, isNot(contains(token)));
    expect(stored, isNot(contains(uuid)));
  }

  test('the factory main uses scrubs what only LogRedactor knows', () {
    final logger = buildAppLogger();
    addTearDown(logger.dispose);
    expectScrubbed(logger);
  });

  test('the provider builds the same logger', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expectScrubbed(container.read(appLoggerProvider));
  });

  test("commy_core's default alone would have let the header through", () {
    // The reason this file exists: if it stops failing here, the wiring
    // above is no longer what makes the difference.
    final bare = AppLogger();
    addTearDown(bare.dispose);
    bare.info(line, tag: 'test');
    expect(bare.buffer.single.message, contains(token));
  });
}
