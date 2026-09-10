import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// DNS policy: two resolvers, an address preference, FakeIP and the cache.
///
/// `DnsSettings` was modelled and generated into the configuration from the
/// first release; this screen is the half that was missing, which meant the
/// row on the routing screen showed a value nobody could change.
///
/// Every control here is rule R6 territory. The two resolvers exist so that a
/// name resolved for the tunnel is never asked outside it and the other way
/// round, so the screen says that out loud rather than presenting them as two
/// interchangeable fields.
class DnsScreen extends ConsumerWidget {
  /// Creates the screen.
  const DnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final dns = ref.watch(dnsSettingsProvider);

    return AdaptiveScaffold(
      appBar: CommyAppBar.section(
        title: t.dns.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.routing),
      ),
      body: AsyncSection<DnsSettings>(
        value: dns,
        skeleton: const ListSkeleton(rows: 6, hasHeader: true),
        onRetry: () => ref.invalidate(dnsSettingsProvider),
        builder: (context, value) => _Body(dns: value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.dns});

  final DnsSettings dns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final controller = ref.read(settingsControllerProvider.notifier);

    return ListView(
      padding: EdgeInsets.only(bottom: spacing.s10),
      children: <Widget>[
        SectionLabel(t.dns.resolvers),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.proxy,
              title: t.dns.remote,
              subtitle: dns.remote,
              isMonospaceSubtitle: true,
              onTap: () => unawaited(
                _edit(
                  context,
                  controller,
                  title: t.dns.remote,
                  current: dns.remote,
                  fallback: DnsSettings.defaultRemote,
                  apply: (value) => dns.copyWith(remote: value),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.direct,
              title: t.dns.direct,
              subtitle: dns.direct,
              isMonospaceSubtitle: true,
              onTap: () => unawaited(
                _edit(
                  context,
                  controller,
                  title: t.dns.direct,
                  current: dns.direct,
                  fallback: DnsSettings.defaultDirect,
                  apply: (value) => dns.copyWith(direct: value),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.all(spacing.s4),
          child: Text(
            t.dns.footer,
            style: context.typography.caption.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ),
        SectionLabel(t.dns.strategy),
        SettingsSection(
          children: <Widget>[
            for (final strategy in DnsStrategy.values)
              SettingsTile(
                title: _strategyLabel(t, strategy),
                trailing: CommyRadio<DnsStrategy>(
                  value: strategy,
                  groupValue: dns.strategy,
                  semanticLabel: _strategyLabel(t, strategy),
                  onChanged: (value) => unawaited(
                    controller.saveDns(dns.copyWith(strategy: value)),
                  ),
                ),
                onTap: () => unawaited(
                  controller.saveDns(dns.copyWith(strategy: strategy)),
                ),
              ),
          ],
        ),
        SectionLabel(t.dns.extra),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.globe,
              title: t.dns.fakeIp,
              subtitle: t.dns.fakeIpHint,
              trailing: CommySwitch(
                value: dns.fakeIp,
                semanticLabel: t.dns.fakeIp,
                onChanged: (value) => unawaited(
                  controller.saveDns(dns.copyWith(fakeIp: value)),
                ),
              ),
            ),
            // The builder turns the cache on regardless while FakeIP is on
            // (`independentCache || fakeIp`), so the switch says so instead of
            // sitting there off while the generated configuration says true.
            SettingsTile(
              icon: CommyIcons.document,
              title: t.dns.independentCache,
              subtitle: dns.fakeIp
                  ? t.dns.independentCacheForced
                  : t.dns.independentCacheHint,
              trailing: CommySwitch(
                value: dns.independentCache || dns.fakeIp,
                semanticLabel: t.dns.independentCache,
                onChanged: dns.fakeIp
                    ? null
                    : (value) => unawaited(
                          controller.saveDns(
                            dns.copyWith(independentCache: value),
                          ),
                        ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.s6),
      ],
    );
  }

  /// Opens the editor and stores what comes back.
  Future<void> _edit(
    BuildContext context,
    SettingsController controller, {
    required String title,
    required String current,
    required String fallback,
    required DnsSettings Function(String value) apply,
  }) async {
    final edited = await CommySheet.show<String>(
      context: context,
      title: title,
      builder: (context) => _ResolverSheet(
        current: current,
        fallback: fallback,
      ),
    );
    if (edited == null) {
      return;
    }
    await controller.saveDns(apply(edited));
  }

  String _strategyLabel(Translations t, DnsStrategy strategy) =>
      switch (strategy) {
        DnsStrategy.preferIpv4 => t.dns.strategyPreferIpv4,
        DnsStrategy.preferIpv6 => t.dns.strategyPreferIpv6,
        DnsStrategy.ipv4Only => t.dns.strategyIpv4Only,
        DnsStrategy.ipv6Only => t.dns.strategyIpv6Only,
      };
}

/// One resolver, checked before it is allowed out of the sheet.
///
/// The check is `DnsSectionBuilder.checkResolver`, which is the same
/// dissection the configuration builder runs. Anything this sheet accepts,
/// the core can be handed; anything it refuses would otherwise have surfaced
/// as a build failure on the next connect, two screens away from the typo.
class _ResolverSheet extends StatefulWidget {
  const _ResolverSheet({required this.current, required this.fallback});

  final String current;
  final String fallback;

  @override
  State<_ResolverSheet> createState() => _ResolverSheetState();
}

class _ResolverSheetState extends State<_ResolverSheet> {
  late final TextEditingController _value = TextEditingController(
    text: widget.current,
  );
  ResolverProblem? _problem;

  @override
  void dispose() {
    _value.dispose();
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
            controller: _value,
            labelText: t.dns.edit.label,
            hintText: t.dns.edit.hint,
            helperText: t.dns.edit.help(schemes: _schemes),
            errorText: _errorText(t),
            autofocus: true,
            isMonospace: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_problem != null) {
                setState(() => _problem = null);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(label: t.common.save, onPressed: _submit),
          SizedBox(height: spacing.s2),
          CommyButton(
            label: t.dns.edit.reset,
            variant: CommyButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(widget.fallback),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  /// The schemes the core actually has a transport for, deduplicated: the
  /// builder maps `dot` and `tls` onto the same one, and listing both twice
  /// would suggest they differ.
  static final String _schemes =
      DnsSectionBuilder.schemes.keys.join(', ');

  String? _errorText(Translations t) => switch (_problem) {
        ResolverProblem.unsupportedScheme => t.dns.edit.unsupportedScheme,
        ResolverProblem.missingAddress => t.dns.edit.missingAddress,
        null => null,
      };

  void _submit() {
    final value = _value.text.trim();
    final problem = DnsSectionBuilder.checkResolver(value);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop(value);
  }
}
