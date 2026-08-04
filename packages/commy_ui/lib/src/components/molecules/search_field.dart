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

  /// When given, a clear button appears and calls this.
  final VoidCallback? onClear;

  /// Whether to take focus on first build.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return CommyTextField(
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      autofocus: autofocus,
      prefixIcon: CommyIcons.search,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      suffix: onClear == null
          ? null
          : CommyIconButton(
              icon: CommyIcons.close,
              onPressed: onClear,
              semanticLabel: clearSemanticLabel,
            ),
    );
  }
}
