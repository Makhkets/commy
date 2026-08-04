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

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
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
        errorText: errorText,
        errorStyle: type.caption.copyWith(color: colors.statusError),
        isDense: true,
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

    final label = labelText;
    if (label == null) {
      return field;
    }
    return Column(
      // Without this the labelled field claims infinite height the moment it
      // is placed in another Column, which is where a form always puts it.
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
    );
  }
}
