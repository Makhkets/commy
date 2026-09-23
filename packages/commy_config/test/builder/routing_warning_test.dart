import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

void main() {
  group('RoutingWarning', () {
    test('two builds that dropped the same thing report equal warnings', () {
      // The app compares the new list with the old one before it rebuilds the
      // routing screen, and a build happens on every connect.
      expect(
        const RoutingWarning(
          RoutingWarningKind.ruleSetsMissing,
          'geosite:ru',
          missing: <String>['geosite-ru'],
        ),
        RoutingWarning(
          RoutingWarningKind.ruleSetsMissing,
          'geosite:ru',
          missing: <String>['geosite-ru'].toList(),
        ),
      );
      expect(
        const RoutingWarning(RoutingWarningKind.ruleSetsMissing, 'geosite:ru')
            .hashCode,
        const RoutingWarning(RoutingWarningKind.ruleSetsMissing, 'geosite:ru')
            .hashCode,
      );
    });

    test('a different kind, subject or list is a different warning', () {
      const base = RoutingWarning(
        RoutingWarningKind.ruleSetsMissing,
        'geosite:ru',
        missing: <String>['geosite-ru'],
      );

      expect(
        base,
        isNot(
          const RoutingWarning(
            RoutingWarningKind.ruleNotApplicable,
            'geosite:ru',
            missing: <String>['geosite-ru'],
          ),
        ),
      );
      expect(
        base,
        isNot(
          const RoutingWarning(
            RoutingWarningKind.ruleSetsMissing,
            'geosite:cn',
            missing: <String>['geosite-ru'],
          ),
        ),
      );
      expect(
        base,
        isNot(
          const RoutingWarning(
            RoutingWarningKind.ruleSetsMissing,
            'geosite:ru',
            missing: <String>['geosite-cn'],
          ),
        ),
      );
    });

    test('the log still gets a whole sentence with the subject in it', () {
      expect(
        const RoutingWarning(
          RoutingWarningKind.adBlockListMissing,
          'geosite-category-ads-all',
        ).toString(),
        contains('"geosite-category-ads-all" is not on disk'),
      );
      expect(
        const RoutingWarning(
          RoutingWarningKind.ruleSetsMissing,
          'geosite:ru',
          missing: <String>['geosite-ru', 'geoip-ru'],
        ).toString(),
        'Rule "geosite:ru" needs geosite-ru, geoip-ru, which is not on disk; '
        'the rule was left out',
      );
    });
  });
}
