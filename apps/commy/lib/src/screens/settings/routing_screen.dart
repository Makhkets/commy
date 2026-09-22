import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/router/app_sections.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Routing: mode, rules in priority order, and the three deeper screens.
///
/// Built simple-to-complex on purpose — docs/05-ux-flows.md expects ninety
/// percent of people to stop after the first row. Dragging is the only way
/// order is expressed, because order **is** priority and any other control
/// would have to explain that in words.
class RoutingScreen extends ConsumerWidget {
  /// Creates the screen.
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final policy = ref.watch(routingPolicyProvider);

    return AdaptiveScaffold(
      destinations: AppSection.destinationsFor(t),
      selectedIndex: AppSection.routing.index,
      onDestinationSelected: (index) => AppSection.select(context, index),
      appBar: CommyAppBar.section(
        title: t.routing.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.settings),
      ),
      body: AsyncSection<RoutingPolicy>(
        value: policy,
        skeleton: const ListSkeleton(rows: 5, hasHeader: true),
        onRetry: () => ref.invalidate(routingPolicyProvider),
        builder: (context, value) => _Body(policy: value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.policy});

  final RoutingPolicy policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final controller = ref.read(settingsControllerProvider.notifier);
    final dns = ref.watch(dnsSettingsProvider).value ?? DnsSettings.defaults;
    final rules = policy.rules;
    final needed = RouteSectionBuilder.requiredRuleSets(
      routing: policy,
      platform: ref.watch(configPlatformProvider),
    ).toSet();
    final ruleSets = <String>{
      for (final set in ref.watch(ruleSetsProvider).value ?? const <RuleSet>[])
        set.tag,
    };

    final warnings = ref.watch(configWarningsProvider);

    // Where a packet that matched nothing actually goes. This row has to
    // agree with `RouteSectionBuilder.finalOutbound`, which answers `direct`
    // in Direct mode and the proxy group in the other two; reading the
    // builder keeps the screen from becoming a second copy of that map that
    // can drift away from the document the core is handed.
    final finalAction =
        RouteSectionBuilder.finalOutbound(policy.mode) == SingBoxTags.direct
            ? RuleAction.direct
            : RuleAction.proxy;

    return ListView(
      padding: EdgeInsets.only(bottom: spacing.s10),
      children: <Widget>[
        if (warnings.isNotEmpty) _DroppedRules(warnings: warnings),
        Padding(
          padding: EdgeInsets.all(spacing.s4),
          child: SegmentedControl<RoutingMode>(
            value: policy.mode,
            segments: <SegmentedControlItem<RoutingMode>>[
              SegmentedControlItem<RoutingMode>(
                value: RoutingMode.global,
                label: t.routing.mode.global,
              ),
              SegmentedControlItem<RoutingMode>(
                value: RoutingMode.rules,
                label: t.routing.mode.rules,
              ),
              SegmentedControlItem<RoutingMode>(
                value: RoutingMode.direct,
                label: t.routing.mode.direct,
              ),
            ],
            onChanged: (mode) => unawaited(controller.setRoutingMode(mode)),
          ),
        ),
        // `RouteSectionBuilder` walks `activeRules` only in Rules mode, so in
        // the other two everything below this line is stored but not in
        // force. The rules are kept — a mode change must not throw a user's
        // work away — and this says so instead, with the one tap that makes
        // them real again.
        if (policy.mode != RoutingMode.rules)
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.s4, 0, spacing.s4, spacing.s3),
            child: ErrorBanner(
              message: t.routing.inactive.body,
              tone: CommyTone.info,
              actionLabel: t.routing.inactive.action,
              onAction: () =>
                  unawaited(controller.setRoutingMode(RoutingMode.rules)),
            ),
          ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.s4,
            end: spacing.s2,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.routing.rulesHint.toUpperCase(),
                  style: context.typography.label.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
              CommyButton(
                label: t.routing.addRule,
                variant: CommyButtonVariant.ghost,
                isCompact: true,
                icon: CommyIcons.add,
                onPressed: () => unawaited(_addRule(context, controller)),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.s2),
        if (rules.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: EmptyState(
              icon: CommyIcons.routing,
              title: t.routing.emptyRules,
              message: t.routing.emptyRulesBody,
              actionLabel: t.routing.addRule,
              onAction: () => unawaited(_addRule(context, controller)),
            ),
          )
        else
          _RuleList(policy: policy),
        // The final outcome is drawn outside the reorderable list because it
        // is not reorderable: routing must end somewhere, and a rule you can
        // drag above the last one is a rule that can be made unreachable.
        RuleRow(
          matcher: t.routing.finalRule,
          actionLabel: _actionLabel(t, finalAction),
          action: finalAction,
          isFinal: true,
        ),
        Padding(
          padding: EdgeInsets.all(spacing.s4),
          child: Text(
            t.routing.finalRuleHint,
            style: context.typography.caption.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ),
        SectionLabel(t.routing.extra),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.server,
              title: t.routing.apps,
              value: policy.perAppMode == PerAppMode.disabled
                  ? t.routing.appsOff
                  : t.routing.appsValue(count: policy.perAppPackages.length),
              onTap: () => context.go(AppRoutes.apps),
            ),
            SettingsTile(
              icon: CommyIcons.globe,
              title: t.routing.ruleSets,
              subtitle: t.routing.ruleSetsHint,
              // How many of the sets the rules ask for are actually here.
              // The old value showed the routing mode, which this row has
              // nothing to do with.
              value: t.routing.ruleSetsValue(
                have: ruleSets.where(needed.contains).length,
                need: needed.length,
              ),
              onTap: () => context.go(AppRoutes.ruleSets),
            ),
            SettingsTile(
              icon: CommyIcons.routing,
              title: t.routing.dns,
              value: t.routing.dnsValue(
                remote: dns.remote,
                strategy: dns.strategy.wireName,
              ),
              onTap: () => context.go(AppRoutes.dns),
            ),
            SettingsTile(
              icon: CommyIcons.direct,
              title: t.routing.bypassLan,
              trailing: CommySwitch(
                value: policy.bypassLan,
                semanticLabel: t.routing.bypassLan,
                onChanged: (value) => unawaited(
                  controller.setBypassLan(enabled: value),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.s6),
      ],
    );
  }

  Future<void> _addRule(
    BuildContext context,
    SettingsController controller,
  ) async {
    final t = Translations.of(context);
    final draft = await CommySheet.show<_RuleDraft>(
      context: context,
      title: t.routing.newRule.title,
      builder: (context) => const _NewRuleSheet(),
    );
    if (draft == null) {
      return;
    }
    await controller.addRule(matcher: draft.matcher, action: draft.action);
  }
}

/// What the last configuration build threw away, and why.
///
/// Every rule naming `geosite:` or a `geoip:` country needs a rule set on
/// disk. Until one is downloaded the builder drops those rules so the tunnel
/// still comes up — correct, but invisible: the rule stays on this screen,
/// looking applied, and does nothing. This is where that stops being silent.
class _DroppedRules extends StatelessWidget {
  const _DroppedRules({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.s4, spacing.s4, spacing.s4, 0),
      child: Container(
        decoration: BoxDecoration(
          color: colors.statusErrorWash,
          borderRadius: context.radii.lgAll,
        ),
        padding: EdgeInsets.all(spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  CommyIcons.warning,
                  size: CommySizes.iconControl,
                  color: colors.statusError,
                ),
                SizedBox(width: spacing.s2),
                Expanded(
                  child: Text(
                    t.routing.dropped.title,
                    style: context.typography.title3.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.s2),
            Text(
              t.routing.dropped.body,
              style: context.typography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            SizedBox(height: spacing.s2),
            for (final warning in warnings) ...<Widget>[
              Text(
                warning,
                style: context.typography.monoSmall.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              SizedBox(height: spacing.s1),
            ],
          ],
        ),
      ),
    );
  }
}

/// The draggable part of the rule list.
class _RuleList extends ConsumerWidget {
  const _RuleList({required this.policy});

  /// The whole policy, not just the rows: a swipe has to be undoable, and
  /// putting a rule back where it was means writing the policy it came from.
  final RoutingPolicy policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final controller = ref.read(settingsControllerProvider.notifier);
    final rules = policy.rules;

    return ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rules.length,
      // `onReorderItem`, not `onReorder`: the newer callback hands over an
      // index that already accounts for the removed row, so the controller
      // does not have to guess which convention it is being given.
      onReorderItem: (from, to) => unawaited(controller.moveRule(from, to)),
      itemBuilder: (context, index) {
        final rule = rules[index];
        return Dismissible(
          key: ValueKey<String>(rule.id),
          direction: DismissDirection.endToStart,
          // A swipe used to be final. A rule is two fields the user typed
          // and an order they arranged, and unlike a server it does not come
          // back with the next subscription refresh — so an accidental swipe
          // on a list you are reordering by hand cost exactly that, silently.
          // The way back is the policy as it stood a moment ago, order and
          // all, and it is offered where the eyes already are.
          onDismissed: (_) {
            unawaited(controller.removeRule(rule.id));
            ToastMessenger.show(
              context,
              message: t.routing.ruleRemoved,
              tone: CommyTone.info,
              icon: CommyIcons.delete,
              actionLabel: t.routing.ruleRestore,
              onAction: () => unawaited(controller.saveRouting(policy)),
            );
          },
          background: ColoredBox(color: context.colors.statusErrorWash),
          child: RuleRow(
            matcher: rule.matcher,
            actionLabel: _actionLabel(t, rule.action),
            action: rule.action,
            dragIndex: index,
            dragHandleLabel: t.a11y.dragRule,
            isEnabled: rule.enabled,
          ),
        );
      },
    );
  }
}

/// The word a badge wears for [action]. Shared so the final outcome and the
/// user's own rules can never disagree about what `direct` is called.
String _actionLabel(Translations t, RuleAction action) => switch (action) {
      RuleAction.proxy => t.routing.action.proxy,
      RuleAction.direct => t.routing.action.direct,
      RuleAction.block => t.routing.action.block,
    };

class _RuleDraft {
  const _RuleDraft(this.matcher, this.action);

  final String matcher;
  final RuleAction action;
}

class _NewRuleSheet extends StatefulWidget {
  const _NewRuleSheet();

  @override
  State<_NewRuleSheet> createState() => _NewRuleSheetState();
}

class _NewRuleSheetState extends State<_NewRuleSheet> {
  final TextEditingController _matcher = TextEditingController();
  RuleAction _action = RuleAction.direct;
  bool _showError = false;

  @override
  void dispose() {
    _matcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyTextField(
            controller: _matcher,
            labelText: t.routing.newRule.matcher,
            hintText: t.routing.newRule.matcherHint,
            errorText: _showError ? t.routing.newRule.empty : null,
            autofocus: true,
            isMonospace: true,
            onChanged: (_) {
              if (_showError) {
                setState(() => _showError = false);
              }
            },
          ),
          SizedBox(height: spacing.s4),
          Text(
            t.routing.newRule.action,
            style: context.typography.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: spacing.s2),
          SegmentedControl<RuleAction>(
            value: _action,
            segments: <SegmentedControlItem<RuleAction>>[
              SegmentedControlItem<RuleAction>(
                value: RuleAction.proxy,
                label: t.routing.action.proxy,
              ),
              SegmentedControlItem<RuleAction>(
                value: RuleAction.direct,
                label: t.routing.action.direct,
              ),
              SegmentedControlItem<RuleAction>(
                value: RuleAction.block,
                label: t.routing.action.block,
              ),
            ],
            onChanged: (action) => setState(() => _action = action),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(
            label: t.routing.newRule.save,
            onPressed: () {
              final matcher = _matcher.text.trim();
              if (matcher.isEmpty) {
                setState(() => _showError = true);
                return;
              }
              Navigator.of(context).pop(_RuleDraft(matcher, _action));
            },
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }
}
