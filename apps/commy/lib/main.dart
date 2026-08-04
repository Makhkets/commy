import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entry point.
///
/// PLACEHOLDER. It exists so the Android build chain — Gradle, the manifest,
/// the libbox AAR and the ProGuard rules — can be verified end to end before
/// the real screens land. The composition root, routing, providers and
/// localisation replace it wholesale.
void main() {
  runApp(const ProviderScope(child: CommyApp()));
}

/// Root widget.
class CommyApp extends StatelessWidget {
  /// Creates the app.
  const CommyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commy',
      debugShowCheckedModeBanner: false,
      theme: CommyTheme.light,
      darkTheme: CommyTheme.dark,
      home: const _BuildProbe(),
    );
  }
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.typography;
    return Scaffold(
      backgroundColor: colors.bgCanvas,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Commy',
              style: type.title1.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'build probe',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
