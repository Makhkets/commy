import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
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
                // A new filter is a new list, not more of the one being read:
                // the pause starts over with it.
                key: ValueKey<(LogLevel?, String)>((_minimum, _query)),
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
  ///
  /// Every way this can end now says so, through the same toast as the rest
  /// of the app. It used to report "скопировано" after a clipboard write
  /// whose result it never looked at, stay silent when the export itself
  /// failed, and claim success over an empty buffer — three different lies
  /// from one button.
  Future<void> _copy(BuildContext context) async {
    final t = Translations.of(context);
    final result = await ref.read(logRepositoryProvider).export(redact: true);
    if (!context.mounted) {
      return;
    }
    final failure = result.failureOrNull;
    if (failure != null) {
      _reportFailure(context, failure);
      return;
    }
    final text = result.valueOrNull ?? '';
    if (text.isEmpty) {
      // Nothing to copy is not a failure and not a success. The empty state
      // of the list already has the sentence for it.
      ToastMessenger.show(
        context,
        message: t.diagnostics.logsEmpty,
        tone: CommyTone.neutral,
        icon: CommyIcons.empty,
      );
      return;
    }
    final written = await ref.read(clipboardProvider).write(text);
    if (!context.mounted) {
      return;
    }
    final writeFailure = written.failureOrNull;
    if (writeFailure != null) {
      _reportFailure(context, writeFailure);
      return;
    }
    ToastMessenger.show(
      context,
      message: t.diagnostics.copied,
      tone: CommyTone.info,
      icon: CommyIcons.copy,
    );
  }

  /// Says why an export or a copy did not happen.
  ///
  /// No route to the logs on the toast: this *is* the log screen, and a
  /// button that navigates to where the user already stands is a dead end
  /// dressed as a way out.
  void _reportFailure(BuildContext context, CommyFailure failure) {
    ToastMessenger.show(
      context,
      message: FailureText.of(failure, Translations.of(context)).message,
      tone: CommyTone.error,
      icon: CommyIcons.warning,
    );
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
    final result = await ref.read(logRepositoryProvider).export(redact: true);
    if (!context.mounted) {
      return;
    }
    final failure = result.failureOrNull;
    if (failure != null) {
      _reportFailure(context, failure);
      return;
    }
    final text = result.valueOrNull ?? '';
    if (text.isEmpty) {
      // The user just read a warning and pressed "export". Returning without
      // a word looks exactly like a button that does nothing.
      ToastMessenger.show(
        context,
        message: t.diagnostics.logsEmpty,
        tone: CommyTone.neutral,
        icon: CommyIcons.empty,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: text, subject: t.diagnostics.title),
    );
  }
}

class _LogBody extends StatefulWidget {
  const _LogBody({
    required this.lines,
    required this.isFiltered,
    required this.onResetFilters,
    required this.onConnect,
    super.key,
  });

  final List<LogLine> lines;

  /// Whether a level or a search term is narrowing [lines].
  final bool isFiltered;

  /// Drops the level and the search term.
  final VoidCallback onResetFilters;

  /// Leads to the connect button.
  final VoidCallback onConnect;

  @override
  State<_LogBody> createState() => _LogBodyState();
}

/// Pauses the list while the user reads.
///
/// The list is newest-last with the newest at the bottom, so a busy core used
/// to move every line under a reader's finger: each new one pushed the rest
/// up by a row (docs/05: "пауза при прокрутке вверх"). Scrolled away from the
/// bottom, the list now holds the lines it had; what arrived since is counted
/// on a button that brings the newest back and lets the list run again.
class _LogBodyState extends State<_LogBody> {
  final ScrollController _scroll = ScrollController();

  /// The lines on screen while paused; `null` while following the tail.
  List<LogLine>? _held;

  /// How far from the bottom still counts as at the bottom — a fling that
  /// stops one line short is not someone reading.
  static const double _tailSlack = 24;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Whether [_toLatest] is scrolling: its own animation passes through
  /// offsets that would otherwise pause the list again on the way down.
  bool _returning = false;

  @override
  void didUpdateWidget(covariant _LogBody old) {
    super.didUpdateWidget(old);
    final held = _held;
    // Cleared while paused: the held lines are gone from the log, and
    // holding on to them would show a list the log no longer has — Copy
    // would then say there is nothing to copy over lines still on screen.
    if (held != null &&
        (widget.lines.isEmpty ||
            (held.isNotEmpty && !_contains(widget.lines, held.last)))) {
      _held = null;
    }
  }

  void _onScroll() {
    final atTail = _scroll.offset <= _tailSlack;
    if (atTail && _held != null) {
      setState(() => _held = null);
    } else if (!atTail && _held == null && !_returning) {
      setState(() => _held = widget.lines);
    }
  }

  static bool _contains(List<LogLine> lines, LogLine line) {
    for (var index = lines.length - 1; index >= 0; index--) {
      if (identical(lines[index], line) || lines[index] == line) {
        return true;
      }
    }
    return false;
  }

  /// Lines that arrived after the last one held.
  int _newSince(List<LogLine> held) {
    if (held.isEmpty) {
      return widget.lines.length;
    }
    final last = held.last;
    for (var index = widget.lines.length - 1; index >= 0; index--) {
      if (identical(widget.lines[index], last) || widget.lines[index] == last) {
        return widget.lines.length - 1 - index;
      }
    }
    // The held lines have scrolled out of the buffer altogether.
    return widget.lines.length;
  }

  void _toLatest() {
    setState(() => _held = null);
    if (!_scroll.hasClients) {
      return;
    }
    // Reduced motion has every duration at zero, and `animateTo` asserts on
    // that; the jump is what the setting asks for anyway.
    if (context.reduceMotion) {
      _scroll.jumpTo(0);
      return;
    }
    _returning = true;
    unawaited(
      _scroll
          .animateTo(
            0,
            duration: context.motion.base,
            curve: context.motion.baseCurve,
          )
          .whenComplete(() => _returning = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final held = _held;
    final lines = held ?? widget.lines;
    final isFiltered = widget.isFiltered;
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
          onAction: widget.onResetFilters,
        );
      }
      return EmptyState(
        icon: CommyIcons.document,
        title: t.diagnostics.logsEmpty,
        message: t.diagnostics.logsEmptyBody,
        actionLabel: t.diagnostics.goConnect,
        onAction: widget.onConnect,
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
      // read is a log nobody reads. The "latest" button sits in a strip under
      // the list rather than over it: on top, it hid the newest held lines —
      // the ones a reader stops to read.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: EdgeInsets.symmetric(vertical: context.spacing.s2),
              itemCount: lines.length,
              itemBuilder: (context, index) =>
                  LogLineView(line: lines[lines.length - 1 - index]),
            ),
          ),
          if (held != null)
            Padding(
              padding: EdgeInsets.all(context.spacing.s2),
              child: Center(
                child: Semantics(
                  hint: t.diagnostics.toLatestHint,
                  child: CommyButton(
                    label: t.diagnostics.toLatest(count: _newSince(held)),
                    icon: CommyIcons.arrowDown,
                    isCompact: true,
                    onPressed: _toLatest,
                  ),
                ),
              ),
            ),
        ],
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
