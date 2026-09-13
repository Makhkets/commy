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
}
