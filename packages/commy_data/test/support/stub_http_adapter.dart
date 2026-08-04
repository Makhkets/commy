import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A dio adapter that answers from a callback instead of from the network.
///
/// A test in this package must never open a socket: rule R1 is about the app,
/// but a test suite that phones home is the same bug with a different blast
/// radius. Everything HTTP-shaped in these tests stops here.
class StubHttpAdapter implements HttpClientAdapter {
  /// Creates an adapter answering through [responder].
  StubHttpAdapter(this.responder);

  /// Answers every request with [body], [statusCode] and [headers].
  factory StubHttpAdapter.text(
    String body, {
    int statusCode = 200,
    Map<String, List<String>> headers = const <String, List<String>>{},
  }) {
    return StubHttpAdapter((_) async {
      return ResponseBody.fromString(body, statusCode, headers: headers);
    });
  }

  /// Fails every request the way a dead host does.
  factory StubHttpAdapter.failing(DioExceptionType type) {
    return StubHttpAdapter((options) async {
      throw DioException(requestOptions: options, type: type);
    });
  }

  /// What answers a request.
  final Future<ResponseBody> Function(RequestOptions options) responder;

  /// Every request this adapter has seen, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}
