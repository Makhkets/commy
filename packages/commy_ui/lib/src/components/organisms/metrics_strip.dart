import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/util/byte_format.dart';
import 'package:commy_ui/src/util/duration_format.dart';
import 'package:flutter/material.dart';

/// Three equal columns: download, session time, upload.
///
/// The clock stays on the connection button's centreline even when the two
/// rates have different widths. Rates are primary; optional session totals
/// are secondary and explicitly labelled. Large text reflows below a centred
/// clock instead of shrinking the reader's chosen type size.
class MetricsStrip extends StatelessWidget {
  /// Creates the readouts. Every label arrives already translated.
  const MetricsStrip({
    required this.uplink,
    required this.downlink,
    required this.session,
    this.isActive = false,
    this.uplinkLabel,
    this.sessionLabel,
    this.downlinkLabel,
    this.uplinkTotal,
    this.downlinkTotal,
    this.totalLabel,
    super.key,
  });

  /// Bytes per second going out.
  final int uplink;

  /// Bytes per second coming in.
  final int downlink;

  /// How long this connection has been up.
  final Duration session;

  /// When false every figure is zero, including optional totals.
  final bool isActive;

  /// Visible, accessible upload label.
  final String? uplinkLabel;

  /// Visible, accessible duration label.
  final String? sessionLabel;

  /// Visible, accessible download label.
  final String? downlinkLabel;

  /// Bytes sent during this session, not a rate.
  final int? uplinkTotal;

  /// Bytes received during this session, not a rate.
  final int? downlinkTotal;

  /// Adds the translated word for "total" to an already formatted volume.
  /// No totals appear unless this formatter and the corresponding count exist.
  final String Function(String value)? totalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final locale = Localizations.maybeLocaleOf(context);
    final color = isActive ? colors.textPrimary : colors.textDisabled;
    String? total(int? bytes) => bytes == null
        ? null
        : totalLabel?.call(
            CommyByteFormat.bytes(isActive ? bytes : 0, locale: locale),
          );

    final down = _Metric(
      icon: CommyIcons.arrowDown,
      value: CommyByteFormat.rate(isActive ? downlink : 0, locale: locale),
      label: downlinkLabel,
      detail: total(downlinkTotal),
      color: color,
    );
    final clock = _Metric(
      icon: CommyIcons.clock,
      value: CommyDurationFormat.clock(isActive ? session : Duration.zero),
      label: sessionLabel,
      color: color,
    );
    final up = _Metric(
      icon: CommyIcons.arrowUp,
      value: CommyByteFormat.rate(isActive ? uplink : 0, locale: locale),
      label: uplinkLabel,
      detail: total(uplinkTotal),
      color: color,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = spacing.s3;
        final available = constraints.maxWidth;
        final column = (available - gap * 2) / 3;
        final downWidth = down.widthOf(context);
        final clockWidth = clock.widthOf(context);
        final upWidth = up.widthOf(context);
        if (downWidth <= column && clockWidth <= column && upWidth <= column) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: down),
              SizedBox(width: gap),
              Expanded(child: clock),
              SizedBox(width: gap),
              Expanded(child: up),
            ],
          );
        }

        final half = (available - gap) / 2;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(child: clock),
            SizedBox(height: spacing.s3),
            if (downWidth <= half && upWidth <= half)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: down),
                  SizedBox(width: gap),
                  Expanded(child: up),
                ],
              )
            else ...<Widget>[
              Center(child: down),
              SizedBox(height: spacing.s3),
              Center(child: up),
            ],
          ],
        );
      },
    );
  }
}

/// A labelled figure, optionally followed by the session's total volume.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.detail,
  });

  final IconData icon;
  final String value;
  final String? label;
  final String? detail;
  final Color color;

  /// Measures the widest line using the same fonts and scale as the readout.
  double widthOf(BuildContext context) {
    final type = context.typography;
    var widest = CommySizes.iconInline;
    for (final (text, style) in <(String?, TextStyle)>[
      (label, type.caption),
      (value, type.numericBody),
      (detail, type.caption),
    ]) {
      if (text == null) continue;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final colors = context.colors;
    final label = this.label;
    final detail = this.detail;
    return Semantics(
      container: true,
      label: label,
      value: detail == null ? value : '$value, $detail',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null)
            Text(
              label,
              textAlign: TextAlign.center,
              style: type.caption.copyWith(color: colors.textSecondary),
            )
          else
            Icon(
              icon,
              size: CommySizes.iconInline,
              color: colors.textSecondary,
            ),
          SizedBox(height: context.spacing.s1),
          Text(
            value,
            textAlign: TextAlign.center,
            style: type.numericBody.copyWith(color: color),
          ),
          if (detail != null) ...<Widget>[
            SizedBox(height: context.spacing.s1),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: type.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
