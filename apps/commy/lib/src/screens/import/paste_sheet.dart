import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A multi-line field for one link or a whole pasted list.
///
/// The field keeps its text when the import fails. Losing thirty pasted links
/// because one of them was malformed is the exact failure docs/05-ux-flows.md
/// calls out: "Экран не закрывается, введённое не теряется".
class PasteSheet extends ConsumerStatefulWidget {
  /// Creates the sheet body.
  const PasteSheet({this.initialText, super.key});

  /// Text the field starts with.
  ///
  /// Filled in when the sheet was opened by a link tapped somewhere else on
  /// the device: the user still sees what is about to be imported and still
  /// presses the button, which is the same contract the clipboard preview has.
  final String? initialText;

  /// Opens the sheet, optionally pre-filled with [initialText].
  static Future<void> show(BuildContext context, {String? initialText}) {
    final title = Translations.of(context).import.paste.title;
    return CommySheet.show<void>(
      context: context,
      title: title,
      builder: (context) => PasteSheet(initialText: initialText),
    );
  }

  @override
  ConsumerState<PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends ConsumerState<PasteSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final state = ref.watch(importControllerProvider);

    if (state.outcome != null || state.failure != null) {
      return const ImportResultPanel();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyTextField(
            controller: _controller,
            labelText: t.import.paste.label,
            hintText: t.import.paste.hint,
            autofocus: true,
            isMonospace: true,
            minLines: _minLines,
            maxLines: _maxLines,
            keyboardType: TextInputType.multiline,
          ),
          SizedBox(height: spacing.s5),
          CommyButton(
            label: t.import.paste.action,
            isLoading: state.isBusy,
            onPressed: _submit,
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  void _submit() {
    unawaited(
      ref.read(importControllerProvider.notifier).importText(_controller.text),
    );
  }

  static const int _minLines = 3;
  static const int _maxLines = 8;
}
