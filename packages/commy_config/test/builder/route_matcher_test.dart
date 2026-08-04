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

    test('drops something it cannot make sense of', () {
      expect(_parse(''), isNull);
      expect(_parse('   '), isNull);
      expect(_parse('unknown_matcher:value'), isNull);
      expect(_parse('domain:'), isNull);
    });
  });
}
