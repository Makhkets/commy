import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// Asks for a backup password, then does the slow part with the sheet open.
///
/// One sheet for both directions. Saving asks twice — a typo there locks the
/// user out of their own backup for good — and says so above the fields;
/// opening asks once. Either way the sheet stays up while [onSubmit] runs,
/// with the button spinning: the key derivation takes seconds on purpose, and
/// a sheet that closed on tap would leave the user looking at nothing.
///
/// [onSubmit] answers with a sentence to show under the field, or null when
/// it is done — then the sheet closes and [show] returns true. A wrong
/// password stays in the sheet with the text kept, so it can be corrected
/// rather than retyped (docs/05, scenario 1).
///
/// The password is never stored, never logged, and never put back into a
/// field once the sheet closes.
class BackupPasswordSheet extends StatefulWidget {
  /// Creates the sheet body.
  @visibleForTesting
  const BackupPasswordSheet({
    required this.confirm,
    required this.submitLabel,
    required this.onSubmit,
    this.body,
    super.key,
  });

  /// Shows the sheet. True when [onSubmit] finished without an objection.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required bool confirm,
    required String submitLabel,
    required Future<String?> Function(String password) onSubmit,
    String? body,
  }) async {
    final done = await CommySheet.show<bool>(
      context: context,
      title: title,
      builder: (context) => BackupPasswordSheet(
        confirm: confirm,
        submitLabel: submitLabel,
        onSubmit: onSubmit,
        body: body,
      ),
    );
    return done ?? false;
  }

  /// Whether the password is asked twice: when it is being chosen.
  final bool confirm;

  /// What the button says.
  final String submitLabel;

  /// Does the work; see the class comment.
  final Future<String?> Function(String password) onSubmit;

  /// A paragraph above the fields.
  final String? body;

  @override
  State<BackupPasswordSheet> createState() => _BackupPasswordSheetState();
}

class _BackupPasswordSheetState extends State<BackupPasswordSheet> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  bool _visible = false;
  bool _working = false;
  String? _passwordError;
  String? _repeatError;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final strings = t.settings.backup.password;
    final spacing = context.spacing;
    final body = widget.body;

    final reveal = CommyIconButton(
      icon: _visible ? CommyIcons.hide : CommyIcons.show,
      semanticLabel: _visible ? strings.hide : strings.show,
      onPressed: () => setState(() => _visible = !_visible),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (body != null) ...<Widget>[
            Text(
              body,
              style: context.typography.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(height: spacing.s4),
          ],
          CommyTextField(
            controller: _password,
            labelText: strings.label,
            prefixIcon: CommyIcons.lock,
            suffix: reveal,
            obscureText: !_visible,
            isSecret: true,
            errorText: _passwordError,
            enabled: !_working,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            textInputAction:
                widget.confirm ? TextInputAction.next : TextInputAction.done,
            onChanged: (_) => _clearErrors(),
            onSubmitted: (_) =>
                widget.confirm ? null : unawaited(_submit(t)),
          ),
          if (widget.confirm) ...<Widget>[
            SizedBox(height: spacing.s3),
            CommyTextField(
              controller: _repeat,
              labelText: strings.repeat,
              prefixIcon: CommyIcons.lock,
              obscureText: !_visible,
              isSecret: true,
              errorText: _repeatError,
              enabled: !_working,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearErrors(),
              onSubmitted: (_) => unawaited(_submit(t)),
            ),
          ],
          SizedBox(height: spacing.s5),
          CommyButton(
            label: widget.submitLabel,
            isLoading: _working,
            onPressed: _working ? null : () => unawaited(_submit(t)),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  void _clearErrors() {
    if (_passwordError != null || _repeatError != null) {
      setState(() {
        _passwordError = null;
        _repeatError = null;
      });
    }
  }

  Future<void> _submit(Translations t) async {
    final strings = t.settings.backup.password;
    // As typed: no trim. Spaces are characters, and a password quietly
    // changed here is a backup its owner cannot open.
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _passwordError = strings.empty);
      return;
    }
    if (widget.confirm) {
      if (password.length < ExportBackupUseCase.minPasswordLength) {
        setState(
          () => _passwordError = strings.tooShort(
            min: ExportBackupUseCase.minPasswordLength,
          ),
        );
        return;
      }
      if (_repeat.text != password) {
        setState(() => _repeatError = strings.mismatch);
        return;
      }
    }
    setState(() => _working = true);
    final objection = await widget.onSubmit(password);
    if (!mounted) {
      return;
    }
    if (objection == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _working = false;
      _passwordError = objection;
    });
  }
}
