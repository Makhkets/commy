import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// The core log: monospace, coloured by level, filtered and searchable.
///
/// Two guarantees hold on this screen and both are rule R3. Copying goes
/// through the repository's redacting export, not through the buffer, so a
/// UUID cannot reach the clipboard. Exporting says, before it runs, exactly
/// what is being stripped — an export the user does not understand is an
/// export they will paste into a public issue.
class LogsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final TextEditingController _search = TextEditingController();
  LogLevel? _minimum;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final lines = ref.watch(logLinesProvider);

    return DiagnosticsShell(
      route: AppRoutes.diagnosticsLogs,
      actions: <Widget>[
        CommyIconButton(
          icon: CommyIcons.copy,
          semanticLabel: t.a11y.copyLogs,
          tooltip: t.diagnostics.copy,
          onPressed: () => unawaited(_copy(context)),
        ),
        CommyIconButton(
          icon: CommyIcons.delete,
          semanticLabel: t.diagnostics.clear,
          tooltip: t.diagnostics.clear,
          onPressed: () => unawaited(
            ref.read(logRepositoryProvider).clear(),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: SearchField(
              controller: _search,
              hintText: t.common.search,
              clearSemanticLabel: t.a11y.clearField,
              onChanged: (value) => setState(() => _query = value.trim()),
              onClear: () => setState(() {
                _search.clear();
                _query = '';
              }),
            ),
          ),
          SizedBox(height: spacing.s3),
          _LevelFilter(
            selected: _minimum,
            onChanged: (level) => setState(() => _minimum = level),
          ),
          SizedBox(height: spacing.s3),
          Expanded(
            child: AsyncSection<List<LogLine>>(
              value: lines,
              skeleton: const ListSkeleton(rows: 8),
              builder: (context, all) => _LogBody(
                lines: _filter(all),
                isFiltered: _isFiltered,
                onResetFilters: _resetFilters,
                onConnect: () => context.go(AppRoutes.home),
              ),
            ),
          ),
          _RedactionNotice(onExport: () => unawaited(_export(context))),
        ],
      ),
    );
  }

  bool get _isFiltered => _minimum != null || _query.isNotEmpty;

  void _resetFilters() => setState(() {
        _search.clear();
        _query = '';
        _minimum = null;
      });

  List<LogLine> _filter(List<LogLine> all) {
    final minimum = _minimum;
    final query = _query.toLowerCase();
    return <LogLine>[
      for (final line in all)
        if ((minimum == null || line.level.passes(minimum)) &&
            (query.isEmpty || line.message.toLowerCase().contains(query)))
          line,
    ];
  }

  /// Copies the **redacted** export, never the buffer.
  Future<void> _copy(BuildContext context) async {
    final t = Translations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result =
        await ref.read(logRepositoryProvider).export(redact: true);
    final text = result.valueOrNull;
    if (text == null) {
      return;
    }
    await ref.read(clipboardProvider).write(text);
    messenger?.showSnackBar(SnackBar(content: Text(t.diagnostics.copied)));
  }

  /// Asks first, and the question says what will be in the file.
  Future<void> _export(BuildContext context) async {
    final t = Translations.of(context);
    final confirmed = await CommySheet.show<bool>(
      context: context,
      title: t.diagnostics.exportWarning.title,
      builder: (context) => _ExportConfirmation(
        body: t.diagnostics.exportWarning.body,
        confirmLabel: t.diagnostics.exportWarning.confirm,
        cancelLabel: t.diagnostics.exportWarning.cancel,
      ),
    );
    if (!(confirmed ?? false)) {
      return;
    }
    final result =
        await ref.read(logRepositoryProvider).export(redact: true);
    final text = result.valueOrNull;
    if (text == null || text.isEmpty) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: text, subject: t.diagnostics.title),
    );
  }
}

class _LogBody extends StatelessWidget {
  const _LogBody({
    required this.lines,
    required this.isFiltered,
    required this.onResetFilters,
    required this.onConnect,
  });

  final List<LogLine> lines;

  /// Whether a level or a search term is narrowing [lines].
  final bool isFiltered;

  /// Drops the level and the search term.
  final VoidCallback onResetFilters;

  /// Leads to the connect button.
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    if (lines.isEmpty) {
      // Two different "nothing here", with two different ways out. A filter
      // that matched nothing is undone on this screen; a log that was never
      // written starts on the home screen, where the connect button is.
      // docs/05-ux-flows.md: an empty state without an action is not one.
      if (isFiltered) {
        return EmptyState(
          icon: CommyIcons.search,
          title: t.diagnostics.logsFiltered,
          message: t.diagnostics.logsFilteredBody,
          actionLabel: t.diagnostics.resetFilters,
          onAction: onResetFilters,
        );
      }
      return EmptyState(
        icon: CommyIcons.document,
        title: t.diagnostics.logsEmpty,
        message: t.diagnostics.logsEmptyBody,
        actionLabel: t.diagnostics.goConnect,
        onAction: onConnect,
      );
    }
    return Container(
      margin: EdgeInsets.symmetric(horizontal: context.spacing.s4),
      decoration: BoxDecoration(
        color: context.colors.bgInset,
        borderRadius: context.radii.mdAll,
      ),
      clipBehavior: Clip.antiAlias,
      // Newest last, scrolled to the bottom: a log you have to scroll down to
      // read is a log nobody reads.
      child: ListView.builder(
        reverse: true,
        padding: EdgeInsets.symmetric(vertical: context.spacing.s2),
        itemCount: lines.length,
        itemBuilder: (context, index) =>
            LogLineView(line: lines[lines.length - 1 - index]),
      ),
    );
  }
}

class _LevelFilter extends StatelessWidget {
  const _LevelFilter({required this.selected, required this.onChanged});

  final LogLevel? selected;
  final ValueChanged<LogLevel?> onChanged;

  /// The three levels worth filtering by. `trace` and `debug` are not offered:
  /// nobody looking for a problem starts by asking for more noise.
  static const List<LogLevel> levels = <LogLevel>[
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  ];

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Row(
        children: <Widget>[
          CommyChip(
            label: t.diagnostics.levelAll,
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final level in levels) ...<Widget>[
            SizedBox(width: spacing.s2),
            CommyChip(
              label: level.wireName.toUpperCase(),
              isSelected: selected == level,
              onTap: () => onChanged(level),
            ),
          ],
        ],
      ),
    );
  }
}

class _RedactionNotice extends StatelessWidget {
  const _RedactionNotice({required this.onExport});

  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.all(spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                CommyIcons.proxy,
                size: CommySizes.iconControl,
                color: colors.statusConnected,
              ),
              SizedBox(width: spacing.s2),
              Expanded(
                child: Text(
                  t.diagnostics.redactionNotice,
                  style: context.typography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.s3),
          CommyButton(
            label: t.diagnostics.export,
            variant: CommyButtonVariant.secondary,
            icon: CommyIcons.externalLink,
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

class _ExportConfirmation extends StatelessWidget {
  const _ExportConfirmation({
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String body;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            body,
            style: context.typography.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          SizedBox(height: spacing.s2),
          CommyButton(
            label: cancelLabel,
            variant: CommyButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }
}
