import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/routing_profiles_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The routing profiles, as a row of chips above the mode (D10).
///
/// One tap switches: the rules of the chosen profile go into force, and the
/// edits made under the one being left are kept in it. A long press opens
/// what else can be done with a profile — rename it, share it as a link
/// (D11), delete it. Until the user makes a second profile, the row shows the
/// one setup there is as "Main" and an offer to make another: profiles cost
/// nothing to someone who never wants them.
class RoutingProfilesRow extends ConsumerWidget {
  /// Creates the row.
  const RoutingProfilesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final profiles =
        ref.watch(routingProfilesProvider).value ?? RoutingProfiles.empty;

    final chips = <Widget>[
      if (!profiles.isInUse)
        CommyChip(label: t.routing.profiles.main, isSelected: true),
      for (final profile in profiles.profiles)
        GestureDetector(
          onLongPress: () =>
              unawaited(_ProfileMenu.show(context, ref, profile, profiles)),
          child: CommyChip(
            label: profile.name,
            isSelected: profile.id == profiles.activeId,
            onTap: profile.id == profiles.activeId
                ? () => unawaited(
                      _ProfileMenu.show(context, ref, profile, profiles),
                    )
                : () => unawaited(_switch(context, ref, profile)),
          ),
        ),
      CommyChip(
        label: t.routing.profiles.add,
        icon: CommyIcons.add,
        onTap: () => unawaited(_create(context, ref)),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.s4, spacing.s3, spacing.s4, 0),
      child: Semantics(
        container: true,
        label: t.routing.profiles.title,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final chip in chips) ...<Widget>[
                chip,
                SizedBox(width: spacing.s2),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switch(
    BuildContext context,
    WidgetRef ref,
    RoutingProfile profile,
  ) async {
    final t = Translations.of(context);
    final ok = await ref
        .read(routingProfilesControllerProvider.notifier)
        .switchTo(profile.id);
    if (!context.mounted) {
      return;
    }
    ToastMessenger.show(
      context,
      message: ok
          ? t.routing.profiles.switched(name: profile.name)
          : t.routing.profiles.failed,
      tone: ok ? CommyTone.connected : CommyTone.error,
      icon: ok ? CommyIcons.success : CommyIcons.warning,
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final name = await CommySheet.show<String>(
      context: context,
      title: t.routing.profiles.newTitle,
      builder: (context) => _NameSheet(body: t.routing.profiles.newBody),
    );
    if (name == null || !context.mounted) {
      return;
    }
    final ok = await ref
        .read(routingProfilesControllerProvider.notifier)
        .saveAs(name, currentName: t.routing.profiles.main);
    if (!ok && context.mounted) {
      ToastMessenger.show(
        context,
        message: t.routing.profiles.failed,
        tone: CommyTone.error,
        icon: CommyIcons.warning,
      );
    }
  }
}

/// What can be done with one profile.
class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu({required this.profile, required this.isActive});

  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    RoutingProfile profile,
    RoutingProfiles profiles,
  ) {
    final t = Translations.of(context);
    return CommySheet.show<void>(
      context: context,
      title: t.routing.profiles.menuTitle(name: profile.name),
      builder: (context) => _ProfileMenu(
        profile: profile,
        isActive: profile.id == profiles.activeId,
      ),
    );
  }

  final RoutingProfile profile;

  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final controller = ref.read(routingProfilesControllerProvider.notifier);
    final navigator = Navigator.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.edit,
              title: t.routing.profiles.rename,
              value: profile.name,
              onTap: () async {
                final name = await CommySheet.show<String>(
                  context: context,
                  title: t.routing.profiles.rename,
                  builder: (context) => _NameSheet(initial: profile.name),
                );
                if (name != null) {
                  await controller.rename(profile.id, name);
                }
                if (navigator.canPop()) {
                  navigator.pop();
                }
              },
            ),
            SettingsTile(
              icon: CommyIcons.link,
              title: t.routing.profiles.share,
              onTap: () async {
                // The live rules for the active profile: its stored copy
                // is refreshed only when it is left.
                final live =
                    isActive ? ref.read(routingPolicyProvider).value : null;
                final link = RoutingProfileLink.encode(
                  live == null ? profile : profile.copyWith(policy: live),
                );
                await ref.read(clipboardProvider).write(link);
                if (context.mounted) {
                  ToastMessenger.show(
                    context,
                    message: t.routing.profiles.shared,
                    tone: CommyTone.info,
                    icon: CommyIcons.copy,
                  );
                }
                if (navigator.canPop()) {
                  navigator.pop();
                }
              },
            ),
            SettingsTile(
              icon: CommyIcons.delete,
              title: t.routing.profiles.delete,
              subtitle: isActive ? t.routing.profiles.activeCannotDelete : null,
              tone: isActive ? CommyTone.neutral : CommyTone.error,
              onTap: isActive
                  ? null
                  : () async {
                      final ok = await controller.remove(profile.id);
                      if (ok && context.mounted) {
                        ToastMessenger.show(
                          context,
                          message: t.routing.profiles.deleted,
                          tone: CommyTone.info,
                          icon: CommyIcons.delete,
                        );
                      }
                      if (navigator.canPop()) {
                        navigator.pop();
                      }
                    },
            ),
          ],
        ),
        SizedBox(height: spacing.s4),
      ],
    );
  }
}

/// One name field and a save button. Pops the trimmed name, or nothing.
class _NameSheet extends StatefulWidget {
  const _NameSheet({this.initial = '', this.body});

  final String initial;

  final String? body;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial);
  bool _showError = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final body = widget.body;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (body != null) ...<Widget>[
            Text(
              body,
              style: context.typography.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(height: spacing.s4),
          ],
          CommyTextField(
            controller: _name,
            labelText: t.routing.profiles.name,
            hintText: t.routing.profiles.nameHint,
            errorText: _showError ? t.subscription.rename.empty : null,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_showError) {
                setState(() => _showError = false);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(label: t.routing.profiles.save, onPressed: _submit),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(name);
  }
}
