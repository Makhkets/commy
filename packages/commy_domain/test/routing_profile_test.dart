import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const home = RoutingPolicy(
    rules: <RoutingRule>[
      RoutingRule(id: 'r1', matcher: 'geosite:ru', action: RuleAction.direct),
    ],
  );
  const travel = RoutingPolicy(mode: RoutingMode.global);

  RoutingProfiles twoProfiles() => RoutingProfiles.empty.saveAs(
        live: home,
        name: 'Travel',
        id: 'travel',
        currentName: 'Main',
        currentId: 'main',
      );

  test('the first save keeps the setup there was, and makes the new active',
      () {
    final profiles = twoProfiles();

    expect(profiles.profiles.map((p) => p.name), <String>['Main', 'Travel']);
    expect(profiles.activeId, 'travel');
    expect(profiles.profiles.first.policy, home);
  });

  test('switching brings the target in and keeps edits of the one left', () {
    // On Travel, the user switched to Global before going back to Main.
    final switched = twoProfiles().switchTo('main', live: travel)!;

    expect(switched.live, home);
    expect(switched.profiles.activeId, 'main');
    expect(
      switched.profiles.profiles.firstWhere((p) => p.id == 'travel').policy,
      travel,
    );
    expect(switched.profiles.switchTo('main', live: home), isNull);
    expect(switched.profiles.switchTo('nope', live: home), isNull);
  });

  test('the active and the last profile cannot be removed', () {
    final profiles = twoProfiles();

    expect(profiles.remove('travel'), isNull);
    final left = profiles.remove('main')!;
    expect(left.profiles.single.id, 'travel');
    expect(left.remove('travel'), isNull);
  });

  test('names are trimmed and clipped, an empty one is not taken', () {
    final profiles = twoProfiles();

    expect(profiles.rename('main', '   ').profiles.first.name, 'Main');
    expect(
      profiles.rename('main', '  ${'x' * 60}  ').profiles.first.name,
      hasLength(RoutingProfiles.maxName),
    );
  });

  test('a list round-trips through JSON; a bad entry costs only itself', () {
    final profiles = twoProfiles();
    final json = profiles.toJson();

    expect(RoutingProfiles.fromJson(json), profiles);
    final broken = <String, Object?>{
      'activeId': 'gone',
      'profiles': <Object?>[
        ...(json['profiles']! as List<Object?>),
        <String, Object?>{'id': 'bad'},
      ],
    };
    final read = RoutingProfiles.fromJson(broken);
    expect(read.profiles, hasLength(2));
    const why = 'An active id that is gone falls back to the first profile.';
    expect(read.activeId, 'main', reason: why);
  });

  test('a backup carries the profiles, and an old backup reads as none', () {
    final snapshot = BackupSnapshot(
      createdAt: DateTime.utc(2026, 10, 5),
      appVersion: '1',
      platform: 'android',
      routingProfiles: twoProfiles(),
    );

    final back = BackupSnapshot.fromJson(snapshot.toJson());
    expect(back.routingProfiles, twoProfiles());
    final old = snapshot.toJson()..remove('routingProfiles');
    expect(BackupSnapshot.fromJson(old).routingProfiles.isInUse, isFalse);
  });
}
