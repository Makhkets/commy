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

    test('a name that does not resolve is "did not answer" too', () async {
      final elapsed = await probe.connectTime(
        'no-such-host.invalid',
        443,
        timeout: const Duration(seconds: 2),
      );

      expect(elapsed, isNull);
    });
  });
}
