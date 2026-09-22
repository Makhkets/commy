import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/router/app_sections.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The apps the tunnel carries, or the apps it lets past.
///
/// The list itself is the one thing the Dart side cannot produce: only the
/// platform knows what is installed. Everything else — the mode, the stored
/// packages, the `include_package` / `exclude_package` the configuration ends
/// up with — has been in place since the first release with no screen to
/// reach it.
///
/// One mode, not two lists. docs/05-ux-flows.md is explicit: "только
/// выбранные" and "все кроме выбранных" are mutually exclusive readings of one
/// set, and offering two lists invites a state where an app is in both.
final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) {
  return ref.watch(systemSettingsProvider).installedApps();
});

/// Per-app routing.
class AppsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final apps = ref.watch(installedAppsProvider);

    return AdaptiveScaffold(
      destinations: AppSection.destinationsFor(t),
      selectedIndex: AppSection.routing.index,
      onDestinationSelected: (index) => AppSection.select(context, index),
      appBar: CommyAppBar.section(
        title: t.apps.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.routing),
      ),
      body: AsyncSection<List<InstalledApp>>(
        value: apps,
        skeleton: const ListSkeleton(rows: 8, hasHeader: true),
        onRetry: () => ref.invalidate(installedAppsProvider),
        builder: (context, value) => _Body(apps: value),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.apps});

  final List<InstalledApp> apps;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _showSystem = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final controller = ref.read(settingsControllerProvider.notifier);
    final policy =
        ref.watch(routingPolicyProvider).value ?? RoutingPolicy.defaults;
    final chosen = policy.perAppPackages.toSet();

    if (widget.apps.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(spacing.s4),
        child: EmptyState(
          icon: CommyIcons.server,
          title: t.apps.empty,
          message: t.apps.emptyBody,
          actionLabel: t.common.back,
          onAction: () => context.go(AppRoutes.routing),
        ),
      );
    }

    final visible = <InstalledApp>[
      for (final app in widget.apps)
        if ((_showSystem || !app.isSystem) && app.matches(_query)) app,
    ];
    // "Nothing matches that" is a lie when something does and the switch is
    // hiding it. Searching for `настрой` with system apps off used to answer
    // "try part of the name, or the package" — advice for a typo the user did
    // not make, next to a button labelled "Clear" that threw the search away
    // and turned the switch on as a side effect nothing announced.
    final hiddenSystemMatches = !_showSystem &&
        widget.apps.any((app) => app.isSystem && app.matches(_query));

    final headers = <Widget>[
      Padding(
        padding: EdgeInsets.all(spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SegmentedControl<PerAppMode>(
              value: policy.perAppMode,
              segments: <SegmentedControlItem<PerAppMode>>[
                SegmentedControlItem<PerAppMode>(
                  value: PerAppMode.disabled,
                  label: t.apps.modeDisabled,
                ),
                SegmentedControlItem<PerAppMode>(
                  value: PerAppMode.include,
                  label: t.apps.modeInclude,
                ),
                SegmentedControlItem<PerAppMode>(
                  value: PerAppMode.exclude,
                  label: t.apps.modeExclude,
                ),
              ],
              onChanged: (mode) => unawaited(
                controller.saveRouting(policy.copyWith(perAppMode: mode)),
              ),
            ),
            SizedBox(height: spacing.s2),
            Text(
              _modeHint(t, policy.perAppMode),
              style: context.typography.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
      // The app itself, first and untouchable. docs/05-ux-flows.md asks for
      // it to be shown greyed with an explanation rather than left out: an
      // absence explains nothing, and this is the one exclusion the user
      // cannot change.
      SettingsSection(
        children: <Widget>[
          SettingsTile(
            icon: CommyIcons.proxy,
            title: t.apps.self,
            subtitle: t.apps.selfHint,
            trailing: const CommyCheckbox(value: false, onChanged: null),
          ),
        ],
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.s4,
          spacing.s4,
          spacing.s4,
          spacing.s2,
        ),
        child: SearchField(
          controller: _search,
          hintText: t.apps.search,
          clearSemanticLabel: t.common.clear,
          onChanged: (value) => setState(() => _query = value),
          onClear: () {
            _search.clear();
            setState(() => _query = '');
          },
        ),
      ),
      SettingsSection(
        children: <Widget>[
          SettingsTile(
            icon: CommyIcons.settings,
            title: t.apps.showSystem,
            trailing: CommySwitch(
              value: _showSystem,
              semanticLabel: t.apps.showSystem,
              onChanged: (value) => setState(() => _showSystem = value),
            ),
          ),
        ],
      ),
      // The count and the reset used to be here, above the list. They are
      // at the bottom now — see the bar below the scroll view.
      Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.s4,
          end: spacing.s2,
          top: spacing.s5,
          bottom: spacing.s2,
        ),
        child: Text(
          t.apps.chosen(count: chosen.length).toUpperCase(),
          style: context.typography.label.copyWith(
            color: colors.textTertiary,
          ),
        ),
      ),
    ];

    // A `CustomScrollView`, and the reason is the list at the end of it.
    // All of this used to be children of one `ListView`, which builds every
    // child it is handed: a phone with 400 applications laid out 400 rows to
    // show eight, every time this screen opened, and the cost grew with the
    // number of applications installed — which is rule R11 with a different
    // name. Only the rows need to be lazy; the controls above them are a
    // fixed handful and stay plain boxes.
    //
    // `DecoratedSliver` keeps the card the rows used to sit in, and the
    // divider is drawn by every row but the first, at
    // `SettingsSection.dividerIndent`, so the result is the same picture.
    // The scroll view, and under it a bar that only exists while something
    // is chosen. The count answered "how many did I tick" and the button was
    // the only way to undo the ticking, and both lived above a list of 120
    // rows: 500pt above the fold, and disposed entirely once scrolled past,
    // so a person halfway down could neither read the count nor reach the
    // reset. A bar is the cheap half of a pinned header — no extent to
    // declare, nothing to clip — and it costs nothing when nothing is
    // selected, because then it is not there.
    final list = CustomScrollView(
      slivers: <Widget>[
        for (final header in headers) SliverToBoxAdapter(child: header),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s4),
              child: hiddenSystemMatches
                  ? EmptyState(
                      icon: CommyIcons.settings,
                      title: t.apps.hiddenBySystem,
                      message: t.apps.hiddenBySystemBody,
                      // Shows them and keeps the search: the query was right.
                      actionLabel: t.apps.showSystem,
                      onAction: () => setState(() => _showSystem = true),
                    )
                  : EmptyState(
                      icon: CommyIcons.search,
                      title: t.apps.nothingFound,
                      message: t.apps.nothingFoundBody,
                      // Clears the search, and only the search.
                      actionLabel: t.common.clear,
                      onAction: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: context.radii.lgAll,
              ),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final app = visible[index];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (index > 0)
                        const CommyDivider(
                          indent: SettingsSection.dividerIndent,
                        ),
                      SettingsTile(
                        title: app.label,
                        subtitle: app.packageName,
                        isMonospaceSubtitle: true,
                        // The whole row picks the app, not only the box
                        // at its far end: choosing apps is the one thing
                        // this screen is for and it is done a dozen times
                        // in a row, and a 358pt row where only a 48pt
                        // square answered left most of the target dead.
                        checked: chosen.contains(app.packageName),
                        onTap: () => unawaited(
                          _toggle(
                            controller,
                            policy,
                            package: app.packageName,
                            chosen: !chosen.contains(app.packageName),
                          ),
                        ),
                        trailing: CommyCheckbox(
                          value: chosen.contains(app.packageName),
                          onChanged: (value) => unawaited(
                            _toggle(
                              controller,
                              policy,
                              package: app.packageName,
                              chosen: value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: spacing.s6 + spacing.s10),
        ),
      ],
    );

    if (chosen.isEmpty) {
      return list;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: list),
        const CommyDivider(),
        ColoredBox(
          color: colors.bgCanvas,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.s4,
                end: spacing.s4,
                top: spacing.s2,
                bottom: spacing.s2,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      t.apps.chosen(count: chosen.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.s2),
                  CommyButton(
                    label: t.apps.selectNone,
                    variant: CommyButtonVariant.ghost,
                    isCompact: true,
                    onPressed: () => unawaited(
                      controller.saveRouting(
                        policy.copyWith(perAppPackages: const <String>[]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Adds or removes one package, keeping the stored order stable.
  ///
  /// Stable because the list is what the configuration is built from, and a
  /// set that reshuffles on every tick would make two identical policies look
  /// like a change to `ReloadUseCase` and restart the core for nothing.
  Future<void> _toggle(
    SettingsController controller,
    RoutingPolicy policy, {
    required String package,
    required bool chosen,
  }) {
    final packages = <String>[
      for (final existing in policy.perAppPackages)
        if (existing != package) existing,
      if (chosen) package,
    ];
    return controller.saveRouting(policy.copyWith(perAppPackages: packages));
  }

  String _modeHint(Translations t, PerAppMode mode) => switch (mode) {
        PerAppMode.disabled => t.apps.modeDisabledHint,
        PerAppMode.include => t.apps.modeIncludeHint,
        PerAppMode.exclude => t.apps.modeExcludeHint,
      };
}
