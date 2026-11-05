import 'package:commy_core/src/wire/probe_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detailed results retain errors and accept legacy native replies', () {
    final errors = <String, String>{};
    final delays = ProbeCodec.decodeOutbounds(
      '{"old":12,"new":{"delay":23},'
      '"bad":{"delay":0,"error":"connection refused"}}',
      onFailure: (tag, reason) => errors[tag] = reason,
    );
    expect(delays['old'], const Duration(milliseconds: 12));
    expect(delays['new'], const Duration(milliseconds: 23));
    expect(delays['bad'], isNull);
    expect(errors, <String, String>{'bad': 'connection refused'});
  });
}
