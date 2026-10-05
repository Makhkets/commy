import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const profile = RoutingProfile(
    id: 'p1',
    name: 'RU direct',
    policy: RoutingPolicy(
      rules: <RoutingRule>[
        RoutingRule(id: 'a', matcher: 'geosite:ru', action: RuleAction.direct),
        RoutingRule(
          id: 'b',
          matcher: 'geoip:ru',
          action: RuleAction.direct,
          sortIndex: 1,
        ),
        RoutingRule(
          id: 'c',
          matcher: 'domain:off.example',
          action: RuleAction.block,
          sortIndex: 2,
          enabled: false,
        ),
      ],
      bypassLan: false,
      blockAds: true,
      perAppMode: PerAppMode.include,
      perAppPackages: <String>['org.example.secret'],
    ),
  );

  String linkOf(Map<String, Object?> json) => 'commy://routing/'
      '${base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '')}';

  test('a profile survives its link: rules in order, switches kept', () {
    final link = RoutingProfileLink.encode(profile);
    final back = RoutingProfileLink.decode(link, id: 'new')!;

    expect(link, startsWith('commy://routing/'));
    expect(back.id, 'new');
    expect(back.name, 'RU direct');
    expect(back.policy.mode, RoutingMode.rules);
    expect(
      back.policy.rules.map((rule) => (rule.matcher, rule.action)),
      <(String, RuleAction)>[
        ('geosite:ru', RuleAction.direct),
        ('geoip:ru', RuleAction.direct),
      ],
      reason: 'A switched-off rule is not part of what is shared.',
    );
    expect(back.policy.bypassLan, isFalse);
    expect(back.policy.blockAds, isTrue);
  });

  test('the per-app list never leaves the phone', () {
    final link = RoutingProfileLink.encode(profile);
    final payload = base64Url.normalize(
      link.substring('commy://routing/'.length),
    );
    final json = utf8.decode(base64Url.decode(payload));

    expect(json, isNot(contains('org.example.secret')));
    expect(
      RoutingProfileLink.decode(link, id: 'x')!.policy.perAppMode,
      PerAppMode.disabled,
    );
  });

  test('refuses what it cannot vouch for', () {
    for (final bad in <String>[
      'commy://routing/!!!',
      'commy://routing/',
      linkOf(<String, Object?>{'v': 2, 'name': 'x', 'mode': 'rules'}),
      linkOf(<String, Object?>{'v': 1, 'name': '', 'mode': 'rules'}),
      linkOf(<String, Object?>{'v': 1, 'name': 'x', 'mode': 'turbo'}),
      linkOf(<String, Object?>{
        'v': 1,
        'name': 'x',
        'mode': 'rules',
        'rules': <Object?>[
          <Object?>['geosite:ru', 'teleport'],
        ],
      }),
      linkOf(<String, Object?>{
        'v': 1,
        'name': 'x',
        'mode': 'rules',
        'rules': <Object?>[
          for (var i = 0; i < 501; i++)
            <Object?>['domain:a$i.example', 'direct'],
        ],
      }),
      'happ://routing/xyz',
    ]) {
      expect(RoutingProfileLink.decode(bad, id: 'x'), isNull, reason: bad);
    }
  });
}
