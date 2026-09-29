import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// The loopback proxy of the IP check asks for a password, and the request
/// has to carry it — on the CONNECT of an https request above all, which is
/// the only kind the check makes. A real socket, because the claim is about
/// what `HttpClient` puts on the wire, not about what a fake adapter accepts.
void main() {
  test('the directive carries the credentials and nothing prints them', () {
    const endpoint = ProxyEndpoint.loopback(
      2080,
      username: 'commy',
      password: 'abc123',
    );

    expect(endpoint.proxyDirective, 'PROXY commy:abc123@127.0.0.1:2080');
    expect(endpoint.toString(), isNot(contains('abc123')));
    expect(
      const ProxyEndpoint.loopback(2080).proxyDirective,
      'PROXY 127.0.0.1:2080',
    );
  });

  test('an https request through it sends them on the CONNECT', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final head = Completer<String>();
    server.listen((socket) {
      final buffer = StringBuffer();
      socket.listen((bytes) {
        buffer.write(latin1.decode(bytes));
        if (buffer.toString().contains('\r\n\r\n') && !head.isCompleted) {
          head.complete(buffer.toString());
          socket
            ..write('HTTP/1.1 407 Proxy Authentication Required\r\n\r\n')
            ..destroy();
        }
      });
    });

    final client = CommyHttpClient(
      userAgent: 'Commy/test',
      tunnelProxy: ProxyEndpoint.loopback(
        server.port,
        username: 'commy',
        password: 'abc123',
      ),
    );
    addTearDown(client.close);
    await client.fetchText(
      Uri.parse('https://ip.example/json'),
      throughTunnel: true,
    );

    final request = await head.future.timeout(const Duration(seconds: 5));
    expect(request, startsWith('CONNECT ip.example:443 '));
    expect(
      request.toLowerCase(),
      contains(
        'proxy-authorization: basic '
        '${base64.encode(utf8.encode('commy:abc123'))}'.toLowerCase(),
      ),
    );
  });
}
