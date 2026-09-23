import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocketLatencyProbe', () {
    const probe = SocketLatencyProbe();

    test('times a server that accepts, and sends it nothing', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = <int>[];
      server.listen((client) => client.listen(received.addAll));

      final elapsed = await probe.connectTime(
        InternetAddress.loopbackIPv4.address,
        server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(elapsed, isNotNull);
      expect(elapsed, lessThan(const Duration(seconds: 2)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        received,
        isEmpty,
        reason: 'A probe is a handshake, not a request.',
      );
    });

    test('a refused connection is "did not answer", not an exception',
        () async {
      // Bound and closed again: a port that was just free and has no listener.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      final elapsed = await probe.connectTime(
        InternetAddress.loopbackIPv4.address,
        port,
        timeout: const Duration(seconds: 2),
      );

      expect(elapsed, isNull);
    });

    test('the clock starts after the name is resolved', () async {
      // A cold lookup used to be timed with the handshake, and a batch that
      // happened to resolve first looked four times further away than the
      // same servers measured a moment later.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((client) => client.destroy());
      var lookedUp = false;
      final probe = SocketLatencyProbe(
        lookup: (host) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          lookedUp = true;
          return <InternetAddress>[InternetAddress.loopbackIPv4];
        },
      );

      final elapsed = await probe.connectTime(
        InternetAddress.loopbackIPv4.address,
        server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(lookedUp, isTrue);
      expect(elapsed, isNotNull);
      expect(elapsed, lessThan(const Duration(milliseconds: 400)));
    });

    test('a lookup that eats the whole budget is "did not answer"', () async {
      final probe = SocketLatencyProbe(
        lookup: (host) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return <InternetAddress>[InternetAddress.loopbackIPv4];
        },
      );

      final elapsed = await probe.connectTime(
        'slow.example',
        443,
        timeout: const Duration(milliseconds: 200),
      );

      expect(elapsed, isNull);
    });

    test('a name that does not resolve is "did not answer" too', () async {
      final elapsed = await probe.connectTime(
        'no-such-host.invalid',
        443,
        timeout: const Duration(seconds: 2),
      );

      expect(elapsed, isNull);
    });
  });

  group('SocketLatencyProbe.echoTime', () {
    test('hands the echo to the platform, with the deadline', () async {
      final asked = <String>[];
      final probe = SocketLatencyProbe(
        echo: (host, {required timeout}) async {
          asked.add('$host ${timeout.inMilliseconds}');
          return const Duration(milliseconds: 23);
        },
      );

      final elapsed = await probe.echoTime(
        '45.151.180.167',
        timeout: const Duration(seconds: 5),
      );

      expect(elapsed, const Duration(milliseconds: 23));
      expect(asked, <String>['45.151.180.167 5000']);
    });

    test('without a platform to send it, no echo is "did not answer"',
        () async {
      expect(
        await const SocketLatencyProbe()
            .echoTime('a.example', timeout: const Duration(seconds: 1)),
        isNull,
      );
    });

    test('a platform that throws is "did not answer" as well', () async {
      final probe = SocketLatencyProbe(
        echo: (host, {required timeout}) async => throw StateError('no'),
      );

      expect(
        await probe.echoTime('a.example', timeout: const Duration(seconds: 1)),
        isNull,
      );
    });
  });
}
