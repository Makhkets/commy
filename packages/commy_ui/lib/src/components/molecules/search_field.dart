import 'package:commy_ui/src/components/atoms/commy_icon_button.dart';
import 'package:commy_ui/src/components/atoms/commy_text_field.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:flutter/material.dart';

/// A text field pre-dressed for filtering a list.
class SearchField extends StatelessWidget {
  /// Creates a search field.
  const SearchField({
    required this.hintText,
    required this.clearSemanticLabel,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onClear,
    this.autofocus = false,
    super.key,
  });

  /// Placeholder text. Already translated.
  final String hintText;

  /// Label announced for the clear button. Already translated.
  final String clearSemanticLabel;

  /// Controller of the query.
  final TextEditingController? controller;

  /// Focus node, when the caller drives focus.
  final FocusNode? focusNode;

  /// Called on every keystroke.
  final ValueChanged<String>? onChanged;

  /// When given, a clear button appears — but only while there is something
  /// to clear — and calls this.
  ///
  /// The cross used to be there from the first frame, on an empty field,
  /// where pressing it cleared nothing: a control that is offered and does
  /// not respond teaches the user to distrust the rest of them. Showing it
  /// needs [controller], which is the only thing that knows whether the
  /// query is empty; without one the button behaves as it always did.
  final VoidCallback? onClear;

  /// Whether to take focus on first build.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final clear = onClear;
    final query = controller;
    if (clear == null || query == null) {
      return _field(hasText: clear != null);
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: query,
      builder: (context, value, _) => _field(hasText: value.text.isNotEmpty),
    );
  }

  Widget _field({required bool hasText}) {
    return CommyTextField(
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      autofocus: autofocus,
      prefixIcon: CommyIcons.search,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      suffix: onClear == null || !hasText
          ? null
          : CommyIconButton(
              icon: CommyIcons.close,
              onPressed: onClear,
              semanticLabel: clearSemanticLabel,
            ),
    );
  }
}
