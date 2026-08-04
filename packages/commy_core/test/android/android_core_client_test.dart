import 'dart:convert';

import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives `AndroidCoreClient` against a mocked Kotlin side.
///
/// The mock answers exactly what `docs/wire-protocol.md` says Kotlin answers,
/// so a change on either side that this file does not know about shows up here
/// rather than as a button that does nothing on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(WireChannels.method);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Map<String, Object?> answers;
  late Map<String, PlatformException> errors;

  setUp(() {
    calls = <MethodCall>[];
    answers = <String, Object?>{};
    errors = <String, PlatformException>{};
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      final error = errors[call.method];
      if (error != null) {
        throw error;
      }
      return answers[call.method];
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(method, null));

  /// Feeds [events] into [channel] the way an `EventChannel` delivers them.
  void mockEvents(String channel, List<Object?> events) {
    messenger.setMockStreamHandler(
      EventChannel(channel),
      _ListStreamHandler(events),
    );
    addTearDown(
      () => messenger.setMockStreamHandler(EventChannel(channel), null),
    );
  }

  group('AndroidCoreClient methods', () {
    test('start hands over the configuration as one JSON string', () async {
      final client = AndroidCoreClient();
      const config = CoreConfig(<String, Object?>{'log': <String, Object?>{}});

      await client.start(config);

      expect(calls.single.method, WireMethods.start);
      expect(calls.single.arguments, config.encode());
    });

    test('stop takes no argument', () async {
      await AndroidCoreClient().stop();

      expect(calls.single.method, WireMethods.stop);
      expect(calls.single.arguments, isNull);
    });

    test('select sends group and tag, not a whole reload', () async {
      await AndroidCoreClient().select('proxy', 'node-7f3c1a');

      expect(calls.single.method, WireMethods.select);
      expect(
        jsonDecode(calls.single.arguments as String),
        <String, Object?>{'group': 'proxy', 'tag': 'node-7f3c1a'},
      );
    });

    test('urlTest sends the probe and reads the delay back', () async {
      answers[WireMethods.urlTest] = '{"delayMs":137}';

      final delay = await AndroidCoreClient().urlTest(
        'node-7f3c1a',
        Uri.parse('http://cp.cloudflare.com/generate_204'),
      );

      expect(delay, const Duration(milliseconds: 137));
      final argument =
          jsonDecode(calls.single.arguments as String) as Map<String, Object?>;
      expect(argument['url'], 'http://cp.cloudflare.com/generate_204');
      expect(argument['group'], 'proxy');
    });

    test('a probe that did not come back is null, not a thrown failure',
        () async {
      answers[WireMethods.urlTest] = '{"delayMs":null}';

      expect(
        await AndroidCoreClient().urlTest('node-1', Uri.parse('http://x/')),
        isNull,
      );
    });

    test('proxies normalises the libbox payload down to the domain shape',
        () async {
      answers[WireMethods.proxies] =
          '[{"tag":"proxy","type":"selector","selected":"nl-03",'
          '"selectable":true,"items":['
          '{"tag":"nl-03","type":"vless","urlTestDelay":48},'
          '{"tag":"de-01","type":"vless","urlTestDelay":0}]}]';

      final groups = await AndroidCoreClient().proxies();

      expect(groups.single.tag, 'proxy');
      expect(groups.single.now, 'nl-03');
      expect(groups.single.all, <String>['nl-03', 'de-01']);
      expect(groups.single.isSelectable, isTrue);
    });

    test('a stopped core reports no groups instead of failing', () async {
      answers[WireMethods.proxies] = '[]';

      expect(await AndroidCoreClient().proxies(), isEmpty);
    });

    test('version is answered as a plain string', () async {
      answers[WireMethods.version] = '1.13.16';

      expect(await AndroidCoreClient().version(), '1.13.16');
    });
  });

  group('AndroidCoreClient failures', () {
    test('a declined VPN prompt arrives as a typed PermissionDeniedFailure',
        () async {
      errors[WireMethods.start] = PlatformException(
        code: WireErrorCodes.permissionDenied,
      );

      await expectLater(
        AndroidCoreClient().start(const CoreConfig(<String, Object?>{})),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const PermissionDeniedFailure(),
          ),
        ),
      );
    });

    test('the same failure survives CoreClientException.failureOf', () async {
      errors[WireMethods.start] = PlatformException(
        code: WireErrorCodes.permissionDenied,
      );

      try {
        await AndroidCoreClient().start(const CoreConfig(<String, Object?>{}));
        fail('start should have thrown');
      } on Object catch (error, stackTrace) {
        // This is the path a use case takes: a blanket catch that must not
        // flatten the code into `unknown` on the way to the screen.
        expect(
          CoreClientException.failureOf(error, stackTrace),
          const PermissionDeniedFailure(),
        );
      }
    });

    test('already_running is treated as a success', () async {
      errors[WireMethods.start] = PlatformException(
        code: WireErrorCodes.alreadyRunning,
      );

      await expectLater(
        AndroidCoreClient().start(const CoreConfig(<String, Object?>{})),
        completes,
      );
    });

    test('config_invalid carries its message to the user', () async {
      errors[WireMethods.select] = PlatformException(
        code: WireErrorCodes.configInvalid,
        message: 'no outbound "node-9" in group "proxy"',
      );

      await expectLater(
        AndroidCoreClient().select('proxy', 'node-9'),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const ConfigInvalidFailure('no outbound "node-9" in group "proxy"'),
          ),
        ),
      );
    });

    test('not_running folds onto helper_unavailable', () async {
      errors[WireMethods.urlTest] = PlatformException(
        code: WireErrorCodes.notRunning,
      );

      await expectLater(
        AndroidCoreClient().urlTest('node-1', Uri.parse('http://x/')),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const HelperUnavailableFailure(),
          ),
        ),
      );
    });

    test('a code from a future version still produces a failure', () async {
      errors[WireMethods.stop] = PlatformException(code: 'from_the_future');

      await expectLater(
        AndroidCoreClient().stop(),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            isA<UnknownFailure>(),
          ),
        ),
      );
    });

    test('a result that will not parse fails rather than answering nothing',
        () async {
      answers[WireMethods.proxies] = 'not json at all';

      await expectLater(
        AndroidCoreClient().proxies(),
        throwsA(isA<CoreClientException>()),
      );
    });

    test('an unregistered plugin means the tunnel service is not there',
        () async {
      // No mock handler at all: exactly what happens on a platform where the
      // Kotlin side was never registered.
      messenger.setMockMethodCallHandler(method, null);

      await expectLater(
        AndroidCoreClient().stop(),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const HelperUnavailableFailure(),
          ),
        ),
      );
    });
  });

  group('AndroidCoreClient streams', () {
    test('reads the status sequence of a normal connect', () async {
      mockEvents(WireChannels.status, <Object?>[
        '{"state":"idle"}',
        '{"state":"starting"}',
        '{"state":"connected","since":1754280000000}',
      ]);

      final states = await AndroidCoreClient().status.take(3).toList();

      expect(states, <Matcher>[
        isA<TunnelIdle>(),
        isA<TunnelStarting>(),
        isA<TunnelConnected>(),
      ]);
    });

    test('keeps `since` when a later event omits it', () async {
      mockEvents(WireChannels.status, <Object?>[
        '{"state":"connected","since":1754280000000}',
        '{"state":"checking"}',
      ]);

      final states = await AndroidCoreClient().status.take(2).toList();

      expect(
        (states.last as TunnelChecking).since,
        (states.first as TunnelConnected).since,
      );
    });

    test('a channel error becomes an error state, not a stream error',
        () async {
      messenger.setMockStreamHandler(
        const EventChannel(WireChannels.status),
        _ErrorStreamHandler(WireErrorCodes.coreCrashed, 'panic: nil map'),
      );
      addTearDown(
        () => messenger.setMockStreamHandler(
          const EventChannel(WireChannels.status),
          null,
        ),
      );

      final state = await AndroidCoreClient().status.first;

      expect(
        state,
        const TunnelStatus.error(CoreCrashedFailure('panic: nil map')),
      );
    });

    test('drops a malformed status event instead of killing the stream',
        () async {
      mockEvents(WireChannels.status, <Object?>[
        'not json',
        '{"state":"connected","since":1754280000000}',
      ]);

      expect(await AndroidCoreClient().status.first, isA<TunnelConnected>());
    });

    test('reads a traffic tick with 64-bit counters', () async {
      const tick = '{"up":25600,"down":37888,"upTotal":1073741824,'
          '"downTotal":5368709120,"at":1754280000000}';
      mockEvents(WireChannels.traffic, <Object?>[tick]);

      final sample = await AndroidCoreClient().traffic.first;

      expect(sample.downlinkTotal, 5368709120);
    });

    test('flattens a batch of log lines into separate events', () async {
      const batch = '[{"level":"info","message":"a","at":1754280000000},'
          '{"level":"error","message":"b","at":1754280000010}]';
      mockEvents(WireChannels.logs, <Object?>[batch]);

      final lines = await AndroidCoreClient().logs.take(2).toList();

      expect(lines.map((line) => line.message), <String>['a', 'b']);
      expect(lines.last.level, LogLevel.error);
    });

    test('reads a connections snapshot whole', () async {
      const payload =
          '[{"id":"c-1", "host":"example.com:443", '
          '"rule":"geosite:ru → direct", "outbound":"direct", '
          '"up":1024, "down":8192, '
          '"start":1754280000000, "network":"tcp"}]';
      mockEvents(WireChannels.connections, <Object?>[payload]);

      final snapshot = await AndroidCoreClient().connections.first;

      expect(snapshot.single.rule, 'geosite:ru → direct');
    });

    test('an error on a data channel reaches the subscriber typed', () async {
      messenger.setMockStreamHandler(
        const EventChannel(WireChannels.traffic),
        _ErrorStreamHandler(WireErrorCodes.storage, 'disk full'),
      );
      addTearDown(
        () => messenger.setMockStreamHandler(
          const EventChannel(WireChannels.traffic),
          null,
        ),
      );

      await expectLater(
        AndroidCoreClient().traffic.first,
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const StorageFailure('disk full'),
          ),
        ),
      );
    });
  });
}

/// Replays a fixed list of payloads to whoever listens.
class _ListStreamHandler extends MockStreamHandler {
  _ListStreamHandler(this.events);

  final List<Object?> events;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink sink) {
    events.forEach(sink.success);
    sink.endOfStream();
  }

  @override
  void onCancel(Object? arguments) {}
}

/// Answers a subscription with one channel error, the way `EventSink.error`
/// arrives on the Dart side.
class _ErrorStreamHandler extends MockStreamHandler {
  _ErrorStreamHandler(this.code, this.message);

  final String code;
  final String message;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink sink) {
    sink
      ..error(code: code, message: message)
      ..endOfStream();
  }

  @override
  void onCancel(Object? arguments) {}
}
