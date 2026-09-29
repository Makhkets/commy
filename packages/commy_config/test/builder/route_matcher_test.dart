import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

RouteMatcher? _parse(String raw, {ConfigPlatform? platform}) =>
    RouteMatcher.tryParse(
      raw,
      platform: platform ?? ConfigPlatform.android,
    );

void main() {
  group('RouteMatcher', () {
    test('reads the domain family', () {
      expect(_parse('domain:a.example')!.fields, <String, Object?>{
        'domain': <String>['a.example'],
      });
      expect(_parse('domain_suffix:a.example')!.fields, <String, Object?>{
        'domain_suffix': <String>['a.example'],
      });
      expect(_parse('keyword:ads')!.fields, <String, Object?>{
        'domain_keyword': <String>['ads'],
      });
      expect(_parse(r'regex:^ads\.')!.fields, <String, Object?>{
        'domain_regex': <String>[r'^ads\.'],
      });
    });

    test('splits a comma separated value', () {
      final matcher = _parse('domain_suffix:a.example,b.example')!;

      expect(matcher.fields, <String, Object?>{
        'domain_suffix': <String>['a.example', 'b.example'],
      });
    });

    test('turns geosite into a rule set reference', () {
      final matcher = _parse('geosite:RU')!;

      expect(matcher.fields, <String, Object?>{
        'rule_set': <String>['geosite-ru'],
      });
      expect(matcher.ruleSets, <String>{'geosite-ru'});
      expect(matcher.matchesDomains, isTrue);
    });

    test('turns geoip:private into a plain flag, not a rule set', () {
      final matcher = _parse('geoip:private')!;

      expect(matcher.fields, <String, Object?>{'ip_is_private': true});
      expect(matcher.ruleSets, isEmpty);
      expect(matcher.matchesDomains, isFalse);
    });

    test('turns a geoip country into a rule set reference', () {
      final matcher = _parse('geoip:nl')!;

      expect(matcher.ruleSets, <String>{'geoip-nl'});
      expect(matcher.matchesDomains, isFalse);
    });

    test('reads addresses and ports', () {
      expect(_parse('ip_cidr:10.0.0.0/8')!.fields, <String, Object?>{
        'ip_cidr': <String>['10.0.0.0/8'],
      });
      expect(_parse('port:443,80')!.fields, <String, Object?>{
        'port': <int>[443, 80],
      });
      expect(_parse('port_range:1000:2000')!.fields, <String, Object?>{
        'port_range': <String>['1000:2000'],
      });
    });

    test('guesses a bare value', () {
      expect(_parse('example.com')!.fields, <String, Object?>{
        'domain_suffix': <String>['example.com'],
      });
      expect(_parse('192.168.0.0/16')!.fields, <String, Object?>{
        'ip_cidr': <String>['192.168.0.0/16'],
      });
      expect(_parse('10.1.2.3')!.fields, <String, Object?>{
        'ip_cidr': <String>['10.1.2.3/32'],
      });
      expect(_parse('ads')!.fields, <String, Object?>{
        'domain_keyword': <String>['ads'],
      });
    });

    test('drops a process matcher on android', () {
      expect(_parse('process_name:curl'), isNull);
      expect(
        _parse('process_name:curl', platform: ConfigPlatform.linux)!.fields,
        <String, Object?>{
          'process_name': <String>['curl'],
        },
      );
    });

    test('drops a package matcher on desktop', () {
      expect(
        _parse('package_name:com.x', platform: ConfigPlatform.linux),
        isNull,
      );
      expect(_parse('package_name:com.x')!.fields, <String, Object?>{
        'package_name': <String>['com.x'],
      });
    });

    test('drops a network value the core does not know', () {
      expect(_parse('network:carrier-pigeon'), isNull);
      expect(_parse('network:udp')!.fields, <String, Object?>{
        'network': <String>['udp'],
      });
    });

    test('writes a port range the way the core reads one', () {
      List<Object?>? rangesOf(String raw) =>
          _parse(raw)!.fields['port_range'] as List<Object?>?;

      // Xray and Clash write a range with a dash; the core refuses the whole
      // document over one ("bad port range").
      expect(rangesOf('port_range:1000-2000'), <String>['1000:2000']);
      expect(rangesOf('port_range:443'), <String>['443:443']);
      expect(
        rangesOf('port_range:1000:2000,3000:'),
        <String>['1000:2000', '3000:65535'],
      );
      expect(rangesOf('port_range::1024'), <String>['0:1024']);
      const bad = <String>['abc', '2000-1000', '1:70000', '-1', '1-2-'];
      for (final range in bad) {
        expect(_parse('port_range:$range')!.isEmpty, isTrue, reason: range);
      }
      expect(rangesOf('port_range:80:90,abc'), <String>['80:90']);
    });

    test('keeps only ports and addresses the core can decode', () {
      // A port is a 16-bit number to the core; an address goes through
      // netip. Anything else fails the whole document rather than one rule.
      expect(_parse('port:443,70000,-1,abc')!.fields, <String, Object?>{
        'port': <int>[443],
      });
      expect(_parse('port:70000')!.isEmpty, isTrue);
      expect(
        _parse('ip_cidr:10.0.0.0/8,10.0.0.0/33,fd00::/8,010.0.0.1')!.fields,
        <String, Object?>{
          'ip_cidr': <String>['10.0.0.0/8', 'fd00::/8'],
        },
      );
      expect(_parse('ip:10.0.0.1')!.fields, <String, Object?>{
        'ip_cidr': <String>['10.0.0.1'],
      });
      for (final bad in <String>['1.2.3', '10.0.0.0/08', 'host.example']) {
        expect(_parse('ip_cidr:$bad')!.isEmpty, isTrue, reason: bad);
      }
      expect(_parse('999.1.1.1')!.isEmpty, isTrue);
    });

    test('drops an expression the core would not compile', () {
      // The core compiles these with Go's regexp; one that fails fails the
      // whole document, and Dart's RegExp alone would let several through.
      for (final bad in <String>[
        '*.example.com',
        r'(?=ads)\.example',
        r'(a)\1',
        r'\q',
        '[]',
        'a{1001}',
      ]) {
        expect(_parse('regex:$bad'), isNull, reason: bad);
      }
      expect(_parse(r'regex:(?i)^ads\.')!.fields, <String, Object?>{
        'domain_regex': <String>[r'(?i)^ads\.'],
      });
      expect(
          _parse(r'regex:^[a-z]{1,3}\.example\.com$')!.fields,
          <String, Object?>{
            'domain_regex': <String>[r'^[a-z]{1,3}\.example\.com$'],
          });
    });

    test('says which matchers need a name resolved into addresses', () {
      bool needs(String raw) => _parse(raw)!.needsResolvedAddress;

      expect(needs('ip_cidr:10.0.0.0/8'), isTrue);
      expect(needs('10.1.2.3'), isTrue);
      expect(needs('geoip:ru'), isTrue);
      expect(needs('rule_set:geoip-ru'), isTrue);
      // The private ranges are for addresses dialled as addresses.
      expect(needs('geoip:private'), isFalse);
      for (final raw in <String>[
        'domain:a.example',
        'geosite:ru',
        'port:443',
        'network:udp',
      ]) {
        expect(needs(raw), isFalse, reason: raw);
      }
    });

    test('drops something it cannot make sense of', () {
      expect(_parse(''), isNull);
      expect(_parse('   '), isNull);
      expect(_parse('unknown_matcher:value'), isNull);
      expect(_parse('domain:'), isNull);
    });
  });
}
