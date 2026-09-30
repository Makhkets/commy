import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// What a subscription calls itself to its panel: the default, a preset, or
/// the user's own string.
///
/// Panels answer by client — base64 to one, Clash YAML to another, nothing at
/// all to a client they do not know — and the default is the honest
/// `Commy/<version>` (docs/06-data-model.md, "User-Agent имеет значение").
/// The override was carried from the entity to the request all along, but
/// nothing in the app could set it, so a panel that only serves known clients
/// could not be fetched in the form the user needed.
///
/// Pops the chosen string, an empty one for the default, or nothing when
/// dismissed.
class UserAgentSheet extends StatefulWidget {
  /// Creates the sheet with [current] selected; `null` is the default.
  const UserAgentSheet({required this.current, super.key});

  /// The override the subscription has now.
  final String? current;

  /// The label a menu row shows for [override].
  ///
  /// The preset's name when it is one — `v2rayNG` reads better than a
  /// version string — the string itself when it is the user's own, and the
  /// product name for the default.
  static String label(String? override) {
    if (override == null) {
      return CommyUserAgent.product;
    }
    for (final preset in CommyUserAgent.presets.entries) {
      if (preset.value == override) {
        return preset.key;
      }
    }
    return override;
  }

  /// Whether [value] can travel as a header.
  ///
  /// `dart:io` throws on anything outside printable ASCII, and a throw there
  /// reads as "the server is not answering" on every refresh.
  static bool isSendable(String value) =>
      value.isNotEmpty && _headerText.hasMatch(value);

  static final RegExp _headerText = RegExp(r'^[\x20-\x7E]+$');

  @override
  State<UserAgentSheet> createState() => _UserAgentSheetState();
}

class _UserAgentSheetState extends State<UserAgentSheet> {
  /// The radio row that stands for the user's own string.
  static const String _custom = '\u0000custom';

  /// The radio row that stands for the default.
  static const String _default = '';

  late String _choice = _initialChoice();
  late final TextEditingController _text = TextEditingController(
    text: _choice == _custom ? widget.current : '',
  );
  bool _showError = false;

  String _initialChoice() {
    final current = widget.current;
    if (current == null) {
      return _default;
    }
    return CommyUserAgent.presets.containsValue(current) ? current : _custom;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final copy = t.subscription.userAgent;

    Widget row({
      required String value,
      required String title,
      String? subtitle,
    }) {
      return SettingsTile(
        title: title,
        subtitle: subtitle,
        isMonospaceSubtitle: subtitle != null,
        selected: _choice == value,
        trailing: CommyRadio<String>(
          value: value,
          groupValue: _choice,
          onChanged: _choose,
        ),
        onTap: () => _choose(value),
      );
    }

    // The section brings its own gutter; everything else is given the same
    // one, so the rows, the field and the button share one edge.
    final gutter = EdgeInsets.symmetric(horizontal: spacing.s4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: gutter,
          child: Text(
            copy.body,
            style: context.typography.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
        SizedBox(height: spacing.s3),
        SettingsSection(
          children: <Widget>[
            row(value: _default, title: copy.honest),
            for (final preset in CommyUserAgent.presets.entries)
              row(
                value: preset.value,
                title: preset.key,
                subtitle: preset.value,
              ),
            row(value: _custom, title: copy.custom),
          ],
        ),
        if (_choice == _custom) ...<Widget>[
          SizedBox(height: spacing.s3),
          Padding(
            padding: gutter,
            child: CommyTextField(
              controller: _text,
              labelText: copy.customLabel,
              errorText: _showError ? copy.invalid : null,
              isMonospace: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_showError) {
                  setState(() => _showError = false);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
        SizedBox(height: spacing.s5),
        Padding(
          padding: gutter,
          child: CommyButton(label: t.common.save, onPressed: _submit),
        ),
        SizedBox(height: spacing.s4),
      ],
    );
  }

  void _choose(String value) => setState(() {
        _choice = value;
        _showError = false;
      });

  void _submit() {
    if (_choice != _custom) {
      Navigator.of(context).pop(_choice);
      return;
    }
    final text = _text.text.trim();
    if (!UserAgentSheet.isSendable(text)) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(text);
  }
}
