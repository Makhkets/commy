import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real dart:io checks, against this machine only — never the internet.
void main() {
  const diagnostics = IoNetworkDiagnostics();
  const timeout = Duration(seconds: 2);

  test('localhost resolves; a reserved name does not', () async {
    final local = await diagnostics.resolve('localhost', timeout: timeout);
    expect(local, isNotEmpty);
    expect(
      await diagnostics.resolve('nothing.invalid', timeout: timeout),
      isNull,
    );
  });

  test('a port nobody listens on is a failed handshake, not a throw', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    expect(
      await diagnostics.tlsHandshake(
        '127.0.0.1',
        port,
        serverName: 'example.test',
        timeout: timeout,
      ),
      TlsOutcome.failed,
    );
  });

  test('a server that speaks no TLS fails the handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((client) {
      client
        ..write('HTTP/1.1 400 Bad Request\r\n\r\n')
        ..destroy();
    });

    expect(
      await diagnostics.tlsHandshake(
        '127.0.0.1',
        server.port,
        serverName: 'example.test',
        timeout: timeout,
      ),
      TlsOutcome.failed,
    );
  });
}
