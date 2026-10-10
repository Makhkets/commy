import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single- or multi-line text input.
///
/// Wraps Material's [TextField] rather than replacing it: text editing is
/// deep platform behaviour — selection handles, autofill, IME, accessibility
/// — and reimplementing it would be a mistake. Only the decoration is ours.
class CommyTextField extends StatelessWidget {
  /// Creates a text field.
  const CommyTextField({
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.isMonospace = false,
    this.isSecret = false,
    super.key,
  });

  /// Controller of the edited text.
  final TextEditingController? controller;

  /// Focus node, when the caller drives focus.
  final FocusNode? focusNode;

  /// Label above the field. Already translated.
  final String? labelText;

  /// Placeholder inside the field. Already translated.
  final String? hintText;

  /// Explanatory line under the field. Already translated.
  final String? helperText;

  /// Error line under the field. Non-null turns the border red.
  final String? errorText;

  /// Optional leading Lucide icon.
  final IconData? prefixIcon;

  /// Optional trailing widget — a clear button, a paste button, a unit.
  final Widget? suffix;

  /// Whether the content is masked.
  final bool obscureText;

  /// How many lines the helper and the error line may take before they are
  /// cut short.
  ///
  /// Material's default is one, with an ellipsis, and the lines that most
  /// need reading are the long ones: the DNS sheet's warning that a system
  /// resolver would leak every name was cut off mid-sentence on a phone, and
  /// its list of schemes with it. A cap rather than no limit, because Material
  /// ellipsizes to a single line when there is none; six is past the longest
  /// sentence the app puts there.
  static const int messageMaxLines = 6;

  /// Whether the field accepts input.
  final bool enabled;

  /// Whether to take focus on first build.
  final bool autofocus;

  /// Maximum number of lines. `null` grows without limit.
  final int? maxLines;

  /// Minimum number of lines.
  final int? minLines;

  /// Soft keyboard type.
  final TextInputType? keyboardType;

  /// What the keyboard's action key does.
  final TextInputAction? textInputAction;

  /// Input filters.
  final List<TextInputFormatter>? inputFormatters;

  /// Called on every edit.
  final ValueChanged<String>? onChanged;

  /// Called when the action key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Whether to render the content in JetBrains Mono. For links, JSON and
  /// anything else where character shape matters more than reading comfort.
  final bool isMonospace;

  /// A secret the keyboard must not learn or suggest from — a password, even
  /// while it is shown in the clear. `obscureText` alone does not say this:
  /// once the user taps "show", the field is ordinary text to the keyboard.
  final bool isSecret;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final radius = context.radii.smAll;
    final hasError = errorText != null;

    OutlineInputBorder borderWith(Color color) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: color,
            // The token happens to equal Flutter's own default today. Naming
            // it anyway is the point of rule R4 — the day the hairline moves,
            // it moves here and not in fourteen widgets.
            // ignore: avoid_redundant_argument_values
            width: CommySizes.borderThin,
          ),
        );

    final textField = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      autocorrect: !isSecret,
      enableSuggestions: !isSecret,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: colors.accentSolid,
      style: (isMonospace ? type.mono : type.body).copyWith(
        color: enabled ? colors.textPrimary : colors.textDisabled,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: colors.bgOverlay,
        hintText: hintText,
        hintStyle: type.body.copyWith(color: colors.textTertiary),
        helperText: helperText,
        helperStyle: type.caption.copyWith(color: colors.textTertiary),
        helperMaxLines: messageMaxLines,
        errorText: errorText,
        errorStyle: type.caption.copyWith(color: colors.statusError),
        errorMaxLines: messageMaxLines,
        isDense: true,
        // `fieldHeight` exists for this and was referenced nowhere: a plain
        // field measured 46pt, two short of both it and `minTapTarget`, and
        // only the search field reached 48 — by accident, because the icon
        // button in its prefix is 48 tall and pushed the row up. A field is
        // something a finger has to land in, and the floor this design
        // system sets for that is 48.
        //
        // `minHeight`, so a multi-line field (the paste sheet asks for
        // three lines and allows eight) keeps growing past it.
        constraints: const BoxConstraints(
          minHeight: CommySizes.fieldHeight,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.s3,
          vertical: spacing.s3,
        ),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(
                prefixIcon,
                size: CommySizes.iconControl,
                color: colors.textTertiary,
              ),
        suffixIcon: suffix,
        border: borderWith(colors.borderDefault),
        enabledBorder:
            borderWith(hasError ? colors.statusError : colors.borderDefault),
        focusedBorder:
            borderWith(hasError ? colors.statusError : colors.borderStrong),
        disabledBorder: borderWith(colors.borderSubtle),
        errorBorder: borderWith(colors.statusError),
        focusedErrorBorder: borderWith(colors.statusError),
      ),
    );

    // A D-pad's up and down leave the field once the caret is at its edge,
    // the way Android's own fields behave: before that they move the caret
    // (to the start or end of a one-line field, a line at a time in a
    // multi-line one), and where there is nothing to go to the key does
    // what it always did. Stopping in the field for good left the switch
    // and the Save button under it out of a remote's reach (the rule sheet,
    // the paste sheet; review of session 25).
    final Widget field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _leaveAtEdge,
      child: textField,
    );

    final label = labelText;
    if (label == null) {
      return field;
    }
    // One node for the label and the field, so the label is the field's
    // name. Drawn as a sibling above it, the label was a node of its own, and
    // a field without a hint was announced as a bare "edit box": the backup
    // password and its repeat, both focused straight away, sounded the same.
    return MergeSemantics(
      child: Column(
        // Without this the labelled field claims infinite height the moment
        // it is placed in another Column, which is where a form always puts
        // it.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: type.captionStrong.copyWith(color: colors.textSecondary),
          ),
          SizedBox(height: spacing.s1),
          field,
        ],
      ),
    );
  }
}

/// Hands the focus to the neighbour above or below when the caret already
/// sits at that edge of the text, and lets everything else through to the
/// field. Runs before the app-wide text-editing shortcuts, being closer to
/// the focused field than they are.
KeyEventResult _leaveAtEdge(FocusNode node, KeyEvent event) {
  if (event is KeyUpEvent || HardwareKeyboard.instance.isShiftPressed) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  final down = key == LogicalKeyboardKey.arrowDown;
  if (!down && key != LogicalKeyboardKey.arrowUp) {
    return KeyEventResult.ignored;
  }
  final focus = primaryFocus;
  final editable = focus?.context?.findAncestorStateOfType<EditableTextState>();
  final value = editable?.textEditingValue;
  if (focus == null || value == null) {
    return KeyEventResult.ignored;
  }
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }
  final atEdge = down
      ? selection.extentOffset >= value.text.length
      : selection.extentOffset <= 0;
  if (!atEdge) {
    return KeyEventResult.ignored;
  }
  final moved = focus.focusInDirection(
    down ? TraversalDirection.down : TraversalDirection.up,
  );
  return moved ? KeyEventResult.handled : KeyEventResult.ignored;
}
