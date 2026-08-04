import 'dart:convert';

import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// The payloads here are copied from `docs/wire-protocol.md`, which is itself
/// written against the libbox API dumped out of the AAR we build. A codec test
/// against invented shapes proves that the codec agrees with the test author.
void main() {
  group('TunnelStatusCodec', () {
    test('reads the connected event from the protocol document', () {
      const raw = '{"state":"connected","since":1754280000000,'
          '"nodeId":null,"reason":null,"code":null}';

      final status = TunnelStatusCodec.decode(raw);

      expect(
        status,
        TunnelStatus.connected(
          since: DateTime.fromMillisecondsSinceEpoch(
            1754280000000,
            isUtc: true,
          ).toLocal(),
        ),
      );
    });

    test('reads the state the native side sends first on onListen', () {
      expect(
        TunnelStatusCodec.decode('{"state":"idle"}'),
        const TunnelStatus.idle(),
      );
    });

    test('turns a dead core into an error state, not into connected', () {
      const raw = '{"state":"error","code":"core_crashed",'
          '"reason":"panic: runtime error"}';

      expect(
        TunnelStatusCodec.decode(raw),
        const TunnelStatus.error(CoreCrashedFailure('panic: runtime error')),
      );
    });

    test('keeps permission_denied typed all the way through', () {
      const raw = '{"state":"error","code":"permission_denied"}';

      expect(
        TunnelStatusCodec.decode(raw),
        const TunnelStatus.error(PermissionDeniedFailure()),
      );
    });

    test('falls back for a connected event with no timestamp', () {
      final fallback = DateTime.utc(2026, 8, 4);

      expect(
        TunnelStatusCodec.decode(
          '{"state":"connected"}',
          fallbackSince: fallback,
        ),
        TunnelStatus.connected(since: fallback),
      );
    });

    test('round-trips every state', () {
      // Local, because the codec reads epoch millis as UTC and hands back
      // local time — the timer on screen runs in the user's clock.
      final since = DateTime.utc(2026, 8, 4, 10).toLocal();
      final states = <TunnelStatus>[
        const TunnelStatus.idle(),
        const TunnelStatus.starting(),
        TunnelStatus.connected(since: since, nodeId: 'node-1'),
        TunnelStatus.checking(since: since, nodeId: 'node-1'),
        const TunnelStatus.stopping(),
        const TunnelStatus.error(PermissionDeniedFailure()),
      ];

      for (final state in states) {
        expect(
          TunnelStatusCodec.decode(jsonEncode(TunnelStatusCodec.encode(state))),
          state,
          reason: '$state did not survive the round trip',
        );
      }
    });

    test('rejects a payload that is not an object at all', () {
      expect(
        () => TunnelStatusCodec.decode('"connected"'),
        throwsA(isA<WireFormatException>()),
      );
    });
  });

  group('TrafficSampleCodec', () {
    test('reads counters past 2^31 without losing precision', () {
      const raw = '{"up":25600,"down":37888,"upTotal":1073741824,'
          '"downTotal":5368709120,"at":1754280000000}';

      final sample = TrafficSampleCodec.decode(raw);

      expect(sample.uplink, 25600);
      expect(sample.downlink, 37888);
      expect(sample.uplinkTotal, 1073741824);
      expect(sample.downlinkTotal, 5368709120);
      expect(sample.at.toUtc().millisecondsSinceEpoch, 1754280000000);
    });

    test('stamps its own time when the core omitted one', () {
      final fallback = DateTime.utc(2026, 8, 4);

      final sample = TrafficSampleCodec.decode(
        '{"up":1,"down":2,"upTotal":3,"downTotal":4}',
        fallbackAt: fallback,
      );

      expect(sample.at, fallback);
    });

    test('treats a missing counter as zero rather than dropping the tick', () {
      expect(TrafficSampleCodec.decode('{}').rate, 0);
    });
  });

  group('LogLineCodec', () {
    test('reads the batch form, which is the one libbox actually sends', () {
      const raw = '[{"level":"info","message":"started","at":1754280000000},'
          '{"level":"error","message":"dial failed","at":1754280000010}]';

      final lines = LogLineCodec.decodeList(raw);

      expect(lines, hasLength(2));
      expect(lines.first.level, LogLevel.info);
      expect(lines.last.level, LogLevel.error);
      expect(lines.last.message, 'dial failed');
    });

    test('reads a single object too', () {
      const raw = '{"level":"warn","message":"slow","at":1754280000000,'
          '"tag":"router"}';

      final lines = LogLineCodec.decodeList(raw);

      expect(lines.single.level, LogLevel.warn);
      expect(lines.single.tag, 'router');
    });

    test('accepts the aliases the core spells its levels with', () {
      expect(
        LogLineCodec.decode('{"level":"warning","message":"x"}').level,
        LogLevel.warn,
      );
      expect(
        LogLineCodec.decode('{"level":"panic","message":"x"}').level,
        LogLevel.fatal,
      );
    });

    test('pulls the level out of an unlabelled sing-box line', () {
      expect(
        LogLineCodec.sniffLevel('INFO[0001] router started'),
        LogLevel.info,
      );
      expect(LogLineCodec.sniffLevel('[warn] fallback in use'), LogLevel.warn);
      expect(
        LogLineCodec.sniffLevel('level=error msg="dial failed"'),
        LogLevel.error,
      );
      expect(LogLineCodec.sniffLevel('just a sentence'), isNull);
    });

    test('keeps the message verbatim, prefix and all', () {
      final line = LogLineCodec.decode('{"message":"INFO[0001] up"}');

      expect(line.level, LogLevel.info);
      expect(line.message, 'INFO[0001] up');
    });

    test('falls back to info for a level nobody recognises', () {
      expect(
        LogLineCodec.decode('{"level":"whatever","message":"x"}').level,
        LogLevel.info,
      );
    });
  });

  group('ConnectionInfoCodec', () {
    test('reads the snapshot from the protocol document', () {
      const raw = '[{"id":"c-1", "host":"example.com:443", '
          '"rule":"geosite:ru → direct", "outbound":"direct", '
          '"up":1024, "down":8192, "start":1754280000000, "network":"tcp"}]';

      final rows = ConnectionInfoCodec.decodeList(raw);

      expect(rows.single.id, 'c-1');
      expect(rows.single.host, 'example.com:443');
      // Without the rule the screen cannot answer the one question it exists
      // for: why is this host not going through the proxy.
      expect(rows.single.rule, 'geosite:ru → direct');
      expect(rows.single.totalBytes, 9216);
      expect(rows.single.network, 'tcp');
    });

    test('skips a row with no id, which no list could keep stable', () {
      const raw = '[{"host":"a:1"},{"id":"c-2","host":"b:2"}]';

      expect(ConnectionInfoCodec.decodeList(raw).single.id, 'c-2');
    });

    test('fills in the defaults the protocol allows', () {
      final start = DateTime.utc(2026, 8, 4);

      final row = ConnectionInfoCodec.decodeList(
        '[{"id":"c-3"}]',
        fallbackStart: start,
      ).single;

      expect(row.host, '');
      expect(row.outbound, '');
      expect(row.uploadTotal, 0);
      expect(row.network, 'tcp');
      expect(row.start, start);
    });
  });

  group('ProxyGroupCodec', () {
    test('reads the groups payload from the protocol document', () {
      const raw = '[{"tag":"auto","type":"urltest","selected":"nl-03",'
          '"selectable":true,'
          '"items":[{"tag":"nl-03","type":"vless","urlTestDelay":48}]}]';

      final groups = ProxyGroupCodec.decodeList(raw);

      expect(groups.single.tag, 'auto');
      expect(groups.single.type, 'urltest');
      expect(groups.single.now, 'nl-03');
      expect(groups.single.all, <String>['nl-03']);
      // Not selectable by hand: `auto` picks for itself.
      expect(groups.single.isSelectable, isFalse);
    });

    test('a stopped core answers with an empty list, not an error', () {
      expect(ProxyGroupCodec.decodeList('[]'), isEmpty);
      expect(ProxyGroupCodec.decodeList(null), isEmpty);
    });

    test('a group with no type stays switchable rather than greying out', () {
      final group = ProxyGroupCodec.decodeList(
        '[{"tag":"proxy","items":[{"tag":"node-1"}]}]',
      ).single;

      expect(group.isSelectable, isTrue);
    });

    test('round-trips through encode', () {
      const group = ProxyGroup(
        tag: 'proxy',
        type: 'selector',
        now: 'node-1',
        all: <String>['node-1', 'node-2'],
      );

      final decoded = ProxyGroupCodec.decodeList(
        jsonEncode(<Object?>[ProxyGroupCodec.encode(group)]),
      ).single;

      expect(decoded, group);
    });
  });

  group('UrlTestCodec', () {
    test('builds the argument the protocol document specifies', () {
      final json = jsonDecode(
        UrlTestCodec.encodeRequest(
          tag: 'node-7f3c1a',
          probe: Uri.parse('http://cp.cloudflare.com/generate_204'),
        ),
      ) as Map<String, Object?>;

      expect(json['tag'], 'node-7f3c1a');
      expect(json['url'], 'http://cp.cloudflare.com/generate_204');
      expect(json['timeoutMs'], 5000);
      expect(json['group'], 'proxy');
    });

    test('reads a measured delay', () {
      expect(
        UrlTestCodec.decodeDelay('{"delayMs":137}'),
        const Duration(milliseconds: 137),
      );
    });

    test('a timeout is null, not an error', () {
      expect(UrlTestCodec.decodeDelay('{"delayMs":null}'), isNull);
      expect(UrlTestCodec.decodeDelay(null), isNull);
    });

    test('zero means unmeasured, which must not sort above a real 12 ms', () {
      expect(UrlTestCodec.decodeDelay('{"delayMs":0}'), isNull);
    });
  });

  group('SelectCodec', () {
    test('builds the argument the protocol document specifies', () {
      expect(
        SelectCodec.encodeRequest(group: 'proxy', tag: 'node-7f3c1a'),
        '{"group":"proxy","tag":"node-7f3c1a"}',
      );
    });

    test('round-trips', () {
      final decoded = SelectCodec.decode(
        SelectCodec.encodeRequest(group: 'proxy', tag: 'node-1'),
      );

      expect(decoded.group, 'proxy');
      expect(decoded.tag, 'node-1');
    });
  });

  group('WireFailureMapper', () {
    test('maps every documented code onto its failure', () {
      expect(
        WireFailureMapper.fromCode(WireErrorCodes.permissionDenied),
        const PermissionDeniedFailure(),
      );
      expect(
        WireFailureMapper.fromCode(WireErrorCodes.notRunning),
        const HelperUnavailableFailure(),
      );
      expect(
        WireFailureMapper.fromCode(WireErrorCodes.configInvalid, message: 'x'),
        const ConfigInvalidFailure('x'),
      );
    });

    test('already_running is a success in disguise', () {
      expect(WireFailureMapper.fromCode(WireErrorCodes.alreadyRunning), isNull);
    });

    test('an unknown code produces a failure instead of a crash', () {
      expect(
        WireFailureMapper.fromCode('from_the_future'),
        isA<UnknownFailure>(),
      );
    });
  });
}
