import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('AppSettings.nodeSort', () {
    test('defaults to panel order, also for settings stored before it existed',
        () {
      expect(AppSettings.defaults.nodeSort, NodeSort.panel);
      expect(
        AppSettings.fromJson(<String, Object?>{'themeMode': 'dark'}).nodeSort,
        NodeSort.panel,
      );
    });

    test('round-trips through JSON', () {
      const settings = AppSettings(nodeSort: NodeSort.latency);

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.nodeSort, NodeSort.latency);
      expect(restored, settings);
    });

    test('copyWith changes only the order', () {
      const settings = AppSettings(hideUnavailable: true);

      final changed = settings.copyWith(nodeSort: NodeSort.name);

      expect(changed.nodeSort, NodeSort.name);
      expect(changed.hideUnavailable, isTrue);
      expect(changed, isNot(settings));
      expect(changed.copyWith(nodeSort: NodeSort.panel), settings);
    });
  });

  group('AppSettings.pingMethod', () {
    test('defaults to GET, also for settings stored before it existed', () {
      expect(AppSettings.defaults.pingMethod, PingMethod.get);
      expect(
        AppSettings.fromJson(<String, Object?>{'themeMode': 'dark'})
            .pingMethod,
        PingMethod.get,
      );
    });

    test('a method this build does not know reads as GET', () {
      expect(
        AppSettings.fromJson(<String, Object?>{'pingMethod': 'udp'})
            .pingMethod,
        PingMethod.get,
      );
    });

    test('round-trips through JSON', () {
      const settings = AppSettings(pingMethod: PingMethod.icmp);

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.pingMethod, PingMethod.icmp);
      expect(restored, settings);
      expect(settings.copyWith(pingMethod: PingMethod.tcp), isNot(settings));
    });
  });

  group('AppSettings.ruleSetUpdateDays', () {
    test('off by default, also for settings stored before it existed', () {
      expect(AppSettings.defaults.ruleSetUpdateDays, 0);
      expect(AppSettings.defaults.isRuleSetAutoUpdateEnabled, isFalse);
      expect(
        AppSettings.fromJson(const <String, Object?>{}).ruleSetUpdateDays,
        0,
      );
    });

    test('round-trips through JSON', () {
      const weekly = AppSettings(ruleSetUpdateDays: 7);

      expect(AppSettings.fromJson(weekly.toJson()), weekly);
    });

    test('an interval nobody offered reads as off', () {
      expect(
        AppSettings.fromJson(const <String, Object?>{'ruleSetUpdateDays': 3})
            .ruleSetUpdateDays,
        0,
      );
    });

    test('no source means no refresh, whatever the interval', () {
      const noSource = AppSettings(ruleSetUpdateDays: 7, ruleSetSource: ' ');

      expect(noSource.isRuleSetAutoUpdateEnabled, isFalse);
    });
  });

  group('AppSettings.ruleSetUrl', () {
    test('each kind of list comes from the repository that publishes it', () {
      const settings = AppSettings.defaults;

      expect(
        settings.ruleSetUrl('geosite-category-ads-all').toString(),
        'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/'
        'geosite-category-ads-all.srs',
      );
      expect(
        settings.ruleSetUrl('geoip-ru').toString(),
        'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/'
        'geoip-ru.srs',
      );
    });

    test('the old default, stored before it could serve geoip, is replaced',
        () {
      final stored = AppSettings.fromJson(<String, Object?>{
        'ruleSetSource': AppSettings.legacyRuleSetSource,
      });

      expect(stored.ruleSetSource, AppSettings.defaultRuleSetSource);
      expect(
        stored.ruleSetUrl('geoip-ru').toString(),
        contains('/SagerNet/sing-geoip/'),
      );
    });

    test('a mirror the user typed is theirs, tokens and all', () {
      const mirror = 'https://mirror.example/{kind}/{tag}.srs';
      final stored = AppSettings.fromJson(<String, Object?>{
        'ruleSetSource': mirror,
      });

      expect(stored.ruleSetSource, mirror);
      expect(
        stored.ruleSetUrl('geoip-ru').toString(),
        'https://mirror.example/geoip/geoip-ru.srs',
      );
      expect(
        const AppSettings(ruleSetSource: 'https://m.example/{tag}.srs')
            .ruleSetUrl('geoip-ru')
            .toString(),
        'https://m.example/geoip-ru.srs',
      );
    });
  });
}
