import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The sections of the app, and the one answer to "where am I".
///
/// `AdaptiveScaffold` draws a rail from 600 dp and a labelled sidebar from
/// 1000 dp — but only for a screen that hands it destinations. An empty list
/// means no permanent navigation at all, which is right on a phone and wrong
/// on everything wider: docs/05-ux-flows.md calls a stretched phone a mistake
/// in as many words. Every screen names its section here rather than building
/// a list of its own, so the entries keep one order everywhere and a deeper
/// screen lights its parent — someone editing DNS is still *in* Routing.
///
/// Below 600 dp `MobileShell` ignores destinations entirely, so naming a
/// section costs a phone nothing and changes nothing there: the gear and the
/// back arrow stay the only way between sections (docs/05-ux-flows.md, "На
/// мобайле нижнего меню нет").
enum AppSection {
  /// The one root screen: the connect button and every server under it. The
  /// power sign is what the screen is *for*, which is why it stands in for a
  /// house here.
  home(AppRoutes.home, CommyIcons.power),

  /// Mode and rules, with apps, rule sets and DNS underneath.
  routing(AppRoutes.routing, CommyIcons.routing),

  /// The four diagnostics tabs. Selecting it lands on the log, because the
  /// hub *is* the log tab — see [AppRoutes.diagnostics].
  diagnostics(AppRoutes.diagnosticsLogs, CommyIcons.diagnostics),

  /// Everything behind the gear, appearance and about included.
  settings(AppRoutes.settings, CommyIcons.settings);

  const AppSection(this.route, this.icon);

  /// Where selecting this section goes.
  final String route;

  /// The glyph the rail and the sidebar draw for it.
  final IconData icon;

  /// The translated name of the section.
  ///
  /// Three of the four already have a name in the settings list, and they
  /// reuse it on purpose: a section called "Маршрутизация" in one place and
  /// "Правила" in another reads as two different destinations.
  String label(Translations t) => switch (this) {
        AppSection.home => t.home.title,
        AppSection.routing => t.settings.routing,
        AppSection.diagnostics => t.settings.diagnostics,
        AppSection.settings => t.settings.title,
      };

  /// The destinations to hand `AdaptiveScaffold`, in [values] order.
  ///
  /// Built from [values] rather than written out, so a screen's
  /// `selectedIndex` is simply its section's [index] and the two can never
  /// drift apart.
  static List<CommyDestination> destinationsFor(Translations t) {
    return <CommyDestination>[
      for (final section in values)
        CommyDestination(icon: section.icon, label: section.label(t)),
    ];
  }

  /// Handles a rail or sidebar selection.
  ///
  /// `go`, not `push`: the rail is a place switcher, and pushing would stack
  /// Routing on top of Settings on top of Home until the back arrow became a
  /// history of clicks rather than a way out.
  static void select(BuildContext context, int index) {
    context.go(values[index].route);
  }
}
