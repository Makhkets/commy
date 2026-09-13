import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The search field and the order chip above the server lists.
///
/// Offered only once there is something to choose between: over a single
/// server both controls would be furniture. The search text lives in
/// [nodeQueryProvider] rather than in this field, so the cards below and the
/// "nothing found" state read the same value, and a reset from that state
/// reaches the field.
class ListToolbar extends ConsumerStatefulWidget {
  /// Creates the toolbar.
  const ListToolbar({super.key});

  @override
  ConsumerState<ListToolbar> createState() => _ListToolbarState();
}

class _ListToolbarState extends ConsumerState<ListToolbar> {
  late final TextEditingController _search =
      TextEditingController(text: ref.read(nodeQueryProvider));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final sort = ref.watch(nodeSortProvider);

    // "Clear the search" on the empty state writes the provider, not this
    // field; the field has to follow or it would keep showing a search that
    // no longer narrows anything.
    ref.listen<String>(nodeQueryProvider, (previous, next) {
      if (next.isEmpty && _search.text.isNotEmpty) {
        _search.clear();
      }
    });

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SearchField(
              controller: _search,
              hintText: t.common.search,
              clearSemanticLabel: t.a11y.clearField,
              onChanged: ref.read(nodeQueryProvider.notifier).write,
              onClear: () {
                _search.clear();
                ref.read(nodeQueryProvider.notifier).clear();
              },
            ),
          ),
          SizedBox(width: spacing.s2),
          CommyChip(
            label: sortLabel(t, sort),
            icon: CommyIcons.arrowDown,
            isSelected: sort != NodeSort.panel,
            onTap: () => unawaited(SortSheet.show(context)),
          ),
        ],
      ),
    );
  }
}

/// The name of [sort] in the current language.
String sortLabel(Translations t, NodeSort sort) => switch (sort) {
      NodeSort.panel => t.home.sort.panel,
      NodeSort.latency => t.home.sort.latency,
      NodeSort.name => t.home.sort.name,
    };

/// Picks how the servers inside each list are ordered.
///
/// One tap chooses and closes: the choice is visible in the list the moment
/// the sheet is gone, which is more confirmation than a second button.
class SortSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SortSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) {
    return CommySheet.show<void>(
      context: context,
      title: Translations.of(context).home.sort.title,
      builder: (context) => const SortSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final current = ref.watch(nodeSortProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SettingsSection(
          children: <Widget>[
            for (final sort in NodeSort.values)
              SettingsTile(
                title: sortLabel(t, sort),
                trailing: sort == current
                    ? Icon(
                        CommyIcons.check,
                        size: CommySizes.iconControl,
                        color: colors.accentSolid,
                      )
                    : null,
                onTap: () {
                  unawaited(
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setNodeSort(sort),
                  );
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        SizedBox(height: spacing.s4),
      ],
    );
  }
}
