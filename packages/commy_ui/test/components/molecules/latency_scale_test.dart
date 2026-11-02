import 'package:commy_ui/commy_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latency boundaries have distinct bars and colours', () {
    for (final (milliseconds, bars, tone) in <(int, int, CommyTone)>[
      (149, 4, CommyTone.connected),
      (150, 2, CommyTone.connecting),
      (300, 2, CommyTone.connecting),
      (301, 1, CommyTone.error),
    ]) {
      final badge = LatencyBadge(
        latency: Duration(milliseconds: milliseconds),
      );
      expect(badge.filledBars, bars);
      expect(badge.tone, tone);
    }
    const unknown = LatencyBadge(latency: null);
    expect(unknown.filledBars, 0);
    expect(unknown.tone, CommyTone.idle);
  });
}
