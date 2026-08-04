import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/relative_time.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adding a subscription: URL, optional name, refresh interval.
///
/// The URL is validated here rather than at the fetcher so that a typo is a
/// field error under the field, not a network failure two seconds later that
/// blames the server for something the user can see and fix.
class SubscriptionSheet extends ConsumerStatefulWidget {
  /// Creates the sheet body.
  const SubscriptionSheet({super.key});

  /// Intervals offered, in hours.
  static const List<int> intervals = <int>[1, 6, 12, 24];

  /// Opens the sheet.
  static Future<void> show(BuildContext context) {
    final title = Translations.of(context).import.subscription.title;
    return CommySheet.show<void>(
      context: context,
      title: title,
      builder: (context) => const SubscriptionSheet(),
    );
  }

  @override
  ConsumerState<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<SubscriptionSheet> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _name = TextEditingController();
  int _intervalHours = Subscription.defaultUpdateIntervalHours;
  bool _autoUpdate = true;
  bool _showUrlError = false;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
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
            controller: _url,
            labelText: t.import.subscription.url,
            hintText: t.import.subscription.urlHint,
            errorText:
                _showUrlError ? t.import.subscription.invalidUrl : null,
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (_) {
              if (_showUrlError) {
                setState(() => _showUrlError = false);
              }
            },
          ),
          SizedBox(height: spacing.s4),
          CommyTextField(
            controller: _name,
            labelText: t.import.subscription.name,
          ),
          SizedBox(height: spacing.s4),
          Text(
            t.import.subscription.interval,
            style: context.typography.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: spacing.s2),
          SegmentedControl<int>(
            value: _intervalHours,
            segments: <SegmentedControlItem<int>>[
              for (final hours in SubscriptionSheet.intervals)
                SegmentedControlItem<int>(
                  value: hours,
                  label: RelativeTime.hours(Duration(hours: hours), t),
                ),
            ],
            onChanged: (hours) => setState(() => _intervalHours = hours),
          ),
          SizedBox(height: spacing.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.import.subscription.autoUpdate,
                  style: context.typography.body.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              CommySwitch(
                value: _autoUpdate,
                semanticLabel: t.import.subscription.autoUpdate,
                onChanged: (value) => setState(() => _autoUpdate = value),
              ),
            ],
          ),
          SizedBox(height: spacing.s5),
          CommyButton(
            label: t.import.subscription.add,
            isLoading: state.isBusy,
            onPressed: _submit,
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  void _submit() {
    final url = Uri.tryParse(_url.text.trim());
    if (url == null || !_isHttp(url)) {
      setState(() => _showUrlError = true);
      return;
    }
    unawaited(
      ref.read(importControllerProvider.notifier).addSubscription(
            url: url,
            name: _name.text,
            autoUpdate: _autoUpdate,
          ),
    );
  }

  /// Only http and https. Rule R1 is about which hosts we reach; this is about
  /// which schemes we are willing to hand to a client at all.
  bool _isHttp(Uri url) {
    final scheme = url.scheme.toLowerCase();
    return url.host.isNotEmpty && (scheme == 'http' || scheme == 'https');
  }
}
