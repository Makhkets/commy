import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// The payloads are shaped like sing-box's Clash API, which spells things
/// differently from our own wire protocol — `type`/`payload` instead of
/// `level`/`message`, RFC 3339 instead of epoch millis, connection metadata in
/// a nested object. Getting that wrong shows up as an empty diagnostics screen
/// on desktop and nowhere else.
void main() {
  group('ClashCodec.decodeProxies', () {
    test('reads groups and drops plain outbounds', () {
      const raw = '{"proxies":{'
          '"proxy":{"type":"Selector","now":"nl-03",'
          '"all":["nl-03","de-01"]},'
          '"nl-03":{"type":"vless","history":[{"delay":48}]},'
          '"direct":{"type":"Direct"}}}';

      final groups = ClashCodec.decodeProxies(raw);

      expect(groups, hasLength(1));
      expect(groups.single.tag, 'proxy');
      expect(groups.single.now, 'nl-03');
      expect(groups.single.all, <String>['nl-03', 'de-01']);
      expect(groups.single.isSelectable, isTrue);
    });

    test('answers empty for a payload with no proxies at all', () {
      expect(ClashCodec.decodeProxies('{}'), isEmpty);
    });
  });

  group('ClashCodec.decodeDelay', () {
    test('reads a measured delay', () {
      expect(
        ClashCodec.decodeDelay('{"delay":137}'),
        const Duration(milliseconds: 137),
      );
    });

    test('zero and missing both mean unmeasured', () {
      expect(ClashCodec.decodeDelay('{"delay":0}'), isNull);
      expect(ClashCodec.decodeDelay('{}'), isNull);
    });
  });

  group('ClashCodec.decodeTraffic', () {
    test('takes the rates from /traffic and the totals from /connections', () {
      final sample = ClashCodec.decodeTraffic(
        '{"up":25600,"down":37888}',
        uplinkTotal: 1073741824,
        downlinkTotal: 5368709120,
        at: DateTime.utc(2026, 8, 4),
      );

      expect(sample.uplink, 25600);
      expect(sample.downlinkTotal, 5368709120);
    });
  });

  group('ClashCodec.decodeLog', () {
    test('reads the Clash spelling', () {
      final line = ClashCodec.decodeLog('{"type":"warning","payload":"slow"}');

      expect(line.level, LogLevel.warn);
      expect(line.message, 'slow');
    });

    test('reads our own spelling too, for debugging one against the other', () {
      final line = ClashCodec.decodeLog('{"level":"error","message":"nope"}');

      expect(line.level, LogLevel.error);
      expect(line.message, 'nope');
    });

    test('falls back to info rather than dropping the line', () {
      expect(ClashCodec.decodeLog('{"payload":"x"}').level, LogLevel.info);
    });
  });

  group('ClashCodec.decodeConnections', () {
    test('reads a snapshot with its metadata and its totals', () {
      const raw = '{"downloadTotal":5368709120,"uploadTotal":1073741824,'
          '"connections":[{"id":"c-1",'
          '"metadata":{"network":"tcp","host":"example.com",'
          '"destinationIP":"93.184.216.34","destinationPort":"443"},'
          '"upload":1024,"download":8192,'
          '"start":"2026-08-04T10:00:00.000Z",'
          '"chains":["proxy","nl-03"],'
          '"rule":"GeoSite","rulePayload":"ru"}]}';

      final snapshot = ClashCodec.decodeConnections(raw);

      expect(snapshot.uplinkTotal, 1073741824);
      expect(snapshot.downlinkTotal, 5368709120);
      final row = snapshot.connections.single;
      expect(row.host, 'example.com:443');
      // Without the rule the screen cannot say why a host went where it went.
      expect(row.rule, 'GeoSite(ru)');
      expect(row.outbound, 'proxy');
      expect(row.totalBytes, 9216);
      expect(
        row.start.toUtc(),
        DateTime.utc(2026, 8, 4, 10),
      );
    });

    test('falls back to the destination IP when there is no host', () {
      const raw = '{"connections":[{"id":"c-2","metadata":'
          '{"destinationIP":"1.1.1.1","destinationPort":"53",'
          '"network":"udp"}}]}';

      final row = ClashCodec.decodeConnections(raw).connections.single;

      expect(row.host, '1.1.1.1:53');
      expect(row.network, 'udp');
    });

    test('accepts epoch millis for start as well as RFC 3339', () {
      const raw = '{"connections":[{"id":"c-3","start":1754280000000}]}';

      final row = ClashCodec.decodeConnections(raw).connections.single;

      expect(row.start.toUtc().millisecondsSinceEpoch, 1754280000000);
    });

    test('skips a row with no id and keeps the rest', () {
      const raw = '{"connections":[{"host":"a"},{"id":"c-4"}]}';

      expect(
        ClashCodec.decodeConnections(raw).connections.single.id,
        'c-4',
      );
    });

    test('an empty snapshot is empty, not an error', () {
      final snapshot = ClashCodec.decodeConnections('{"connections":null}');

      expect(snapshot.connections, isEmpty);
      expect(snapshot.uplinkTotal, 0);
    });
  });
}
