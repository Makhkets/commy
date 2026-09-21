import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_config/src/internal/xhttp_range.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';
import 'package:test/test.dart';

void main() {
  group('XhttpRange', () {
    test('reads every shape Xray accepts', () {
      expect(XhttpRange.tryParse(5), const XhttpRange(5, 5));
      expect(XhttpRange.tryParse('5'), const XhttpRange(5, 5));
      expect(XhttpRange.tryParse('100-1000'), const XhttpRange(100, 1000));
      expect(XhttpRange.tryParse(' 16 - 32 '), const XhttpRange(16, 32));
      expect(XhttpRange.tryParse('-1'), const XhttpRange(-1, -1));
      expect(
        XhttpRange.tryParse(<String, Object?>{'from': 1, 'to': 2}),
        const XhttpRange(1, 2),
      );
      expect(XhttpRange.tryParse(3.0), const XhttpRange(3, 3));
    });

    test('puts ends given backwards in order', () {
      expect(XhttpRange.tryParse('1000-100'), const XhttpRange(100, 1000));
    });

    test('reads nonsense as nothing rather than throwing', () {
      for (final raw in <Object?>[
        null,
        '',
        'a-b',
        '1-',
        true,
        1.5,
        <int>[1],
      ]) {
        expect(XhttpRange.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('writes a fixed value as a number and a span as text', () {
      expect(const XhttpRange(7, 7).toWire(), 7);
      expect(const XhttpRange(1, 9).toWire(), '1-9');
    });
  });

  group('XhttpSettings.read', () {
    test('reads one set of settings in all three spellings', () {
      final xray = XhttpSettings.read(<String, Object?>{
        'xPaddingBytes': '200-400',
        'noGRPCHeader': true,
        'scMaxEachPostBytes': 500000,
        'xmux': <String, Object?>{'maxConcurrency': '16-32'},
      });
      final core = XhttpSettings.read(<String, Object?>{
        'x_padding_bytes': '200-400',
        'no_grpc_header': true,
        'sc_max_each_post_bytes': 500000,
        'xmux': <String, Object?>{'max_concurrency': '16-32'},
      });
      final clash = XhttpSettings.read(<String, Object?>{
        'x-padding-bytes': '200-400',
        'no-grpc-header': true,
        'sc-max-each-post-bytes': 500000,
        'reuse-settings': <String, Object?>{'max-concurrency': '16-32'},
      });

      expect(core.toCore(), xray.toCore());
      expect(clash.toCore(), xray.toCore());
      expect(xray.toCore(), <String, Object?>{
        'x_padding_bytes': '200-400',
        'no_grpc_header': true,
        'sc_max_each_post_bytes': 500000,
        'xmux': <String, Object?>{'max_concurrency': '16-32'},
      });
    });

    test('reads both names Xray has had for the session keys', () {
      final before = XhttpSettings.read(<String, Object?>{
        'sessionPlacement': 'header',
        'sessionKey': 'X-S',
      });
      final after = XhttpSettings.read(<String, Object?>{
        'sessionIDPlacement': 'header',
        'sessionIDKey': 'X-S',
      });

      expect(after.toCore(), before.toCore());
      expect(before.toCore(), <String, Object?>{
        'session_placement': 'header',
        'session_key': 'X-S',
      });
    });

    test('writes those keys under both names, for an Xray of either age', () {
      final xray = XhttpSettings.read(<String, Object?>{
        'session_placement': 'query',
      }).toXray();

      expect(xray['sessionPlacement'], 'query');
      expect(xray['sessionIDPlacement'], 'query');
    });

    test('leaves out what only a server reads, and every default', () {
      final settings = XhttpSettings.read(<String, Object?>{
        'noSSEHeader': true,
        'scMaxBufferedPosts': 30,
        'scStreamUpServerSecs': '20-80',
        'serverMaxHeaderBytes': 8192,
        'noGRPCHeader': false,
        'xPaddingBytes': 0,
        'xmux': <String, Object?>{'hKeepAlivePeriod': 0, 'maxConnections': 0},
      });

      expect(settings.isEmpty, isTrue);
      expect(settings.toCore(), isEmpty);
      expect(settings.toExtraJson(), isNull);
    });

    test('takes a Host header for what it means', () {
      final settings = XhttpSettings.read(<String, Object?>{
        'headers': <String, Object?>{
          'host': 'front.example',
          'X-Api-Key': 'k',
          'Bad': <String, Object?>{},
        },
      });

      expect(settings.hostHeader, 'front.example');
      expect(settings.headers, <String, String>{'X-Api-Key': 'k'});
    });

    test('keeps a download route for export and out of the core', () {
      final settings = XhttpSettings.read(<String, Object?>{
        'downloadSettings': <String, Object?>{'address': 'dl.example'},
      });

      expect(settings.hasDownloadSettings, isTrue);
      expect(settings.toCore(), isEmpty);
      expect(settings.toXray()['downloadSettings'], isNotNull);
    });

    test('never throws on a document from the internet', () {
      final settings = XhttpSettings.read(<String, Object?>{
        'xPaddingBytes': <int>[1, 2],
        'noGRPCHeader': 'maybe',
        'xmux': 'yes please',
        'headers': 'no',
        'sessionPlacement': <String, Object?>{},
      });

      expect(settings.isEmpty, isTrue);
    });
  });

  group('XhttpSettings.tryParseExtra', () {
    test('reads the JSON object of a share link', () {
      final settings =
          XhttpSettings.tryParseExtra('{"xPaddingBytes":"1-2","x":1}');

      expect(settings?.toCore(), <String, Object?>{'x_padding_bytes': '1-2'});
    });

    test('is null for anything that is not a JSON object', () {
      for (final raw in <String?>[null, '', '  ', 'not json', '[1]', '"x"']) {
        expect(XhttpSettings.tryParseExtra(raw), isNull, reason: '$raw');
      }
    });

    test('survives a round trip through its own JSON', () {
      const source = '{"xPaddingBytes":"5-9","noGRPCHeader":true,'
          '"xmux":{"hMaxRequestTimes":"600-900","hKeepAlivePeriod":-1},'
          '"headers":{"X-A":"b"}}';
      final first = XhttpSettings.tryParseExtra(source)!;
      final second = XhttpSettings.tryParseExtra(first.toExtraJson())!;

      expect(second.toCore(), first.toCore());
      expect(
        (jsonDecode(first.toExtraJson()!) as Map<String, Object?>)['xmux'],
        <String, Object?>{
          'hMaxRequestTimes': '600-900',
          'hKeepAlivePeriod': -1,
        },
      );
    });
  });

  group('XhttpSettings.validate refuses what Xray refuses', () {
    void refuses(String mode, Map<String, Object?> source, String what) {
      expect(
        () => XhttpSettings.read(source).validate(mode),
        throwsA(
          isA<ConfigBuildException>().having(
            (error) => error.reason,
            'reason',
            contains(what),
          ),
        ),
        reason: what,
      );
    }

    test('a mode that does not exist', () {
      refuses('stream-down', const <String, Object?>{}, 'stream-down');
    });

    test('padding that is switched off', () {
      refuses('auto', <String, Object?>{'xPaddingBytes': '0-100'}, 'padding');
      refuses('auto', <String, Object?>{'xPaddingBytes': -5}, 'padding');
    });

    test('placements and methods that do not exist', () {
      refuses(
        'auto',
        <String, Object?>{'xPaddingPlacement': 'body'},
        'xPaddingPlacement',
      );
      refuses(
        'auto',
        <String, Object?>{'xPaddingMethod': 'random'},
        'xPaddingMethod',
      );
      refuses(
        'auto',
        <String, Object?>{'sessionPlacement': 'body'},
        'sessionPlacement',
      );
      refuses(
        'auto',
        <String, Object?>{'seqPlacement': 'body'},
        'seqPlacement',
      );
      refuses(
        'packet-up',
        <String, Object?>{'uplinkDataPlacement': 'query'},
        'uplinkDataPlacement',
      );
    });

    test('an upload in headers or by GET outside packet-up', () {
      refuses(
        'stream-up',
        <String, Object?>{'uplinkDataPlacement': 'header'},
        'packet-up',
      );
      // `auto` is not packet-up: with Reality it resolves to stream-one.
      refuses(
        'auto',
        <String, Object?>{'uplinkDataPlacement': 'cookie'},
        'packet-up',
      );
      refuses(
        'stream-one',
        <String, Object?>{'uplinkHTTPMethod': 'get'},
        'packet-up',
      );
    });

    test('a session alphabet that cannot tell sessions apart', () {
      refuses(
        'auto',
        <String, Object?>{'sessionIDTable': 'number', 'sessionIDLength': '2-3'},
        'too few',
      );
      refuses(
        'auto',
        <String, Object?>{'sessionIDTable': 'hex'},
        'sessionIDLength',
      );
      refuses(
        'auto',
        <String, Object?>{
          'sessionIDTable': 'абвгдежзийклмнопрст',
          'sessionIDLength': 20,
        },
        'ASCII',
      );
    });

    test('a session id long enough to stall the core at start', () {
      refuses(
        'auto',
        <String, Object?>{
          'sessionIDTable': 'hex',
          'sessionIDLength': '16-2000000000',
        },
        'longer',
      );
    });

    test('both XMUX limits at once', () {
      refuses(
        'auto',
        <String, Object?>{
          'xmux': <String, Object?>{'maxConnections': 2, 'maxConcurrency': 4},
        },
        'xmux',
      );
    });

    test('and accepts everything in a well formed block', () {
      XhttpSettings.read(<String, Object?>{
        'xPaddingBytes': '100-1000',
        'xPaddingObfsMode': true,
        'xPaddingPlacement': 'cookie',
        'xPaddingMethod': 'tokenish',
        'uplinkDataPlacement': 'header',
        'uplinkHTTPMethod': 'GET',
        'sessionPlacement': 'query',
        'seqPlacement': 'cookie',
        'sessionIDTable': 'base36',
        'sessionIDLength': '16-24',
        'xmux': <String, Object?>{'maxConcurrency': '16-32'},
      }).validate('packet-up');
    });
  });
}
