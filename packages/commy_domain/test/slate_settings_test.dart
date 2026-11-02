import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  test('new settings default to slate, including older empty documents', () {
    expect(
      AppSettings.defaults.themeMode,
      AppThemeMode.slate,
    );
    expect(
      AppSettings.fromJson(<String, Object?>{}).themeMode,
      AppThemeMode.slate,
    );
  });

  test('every explicit preference survives reading and writing', () {
    for (final mode in AppThemeMode.values) {
      final settings = AppSettings.defaults.copyWith(themeMode: mode);
      expect(AppSettings.fromJson(settings.toJson()).themeMode, mode);
    }
  });
}
