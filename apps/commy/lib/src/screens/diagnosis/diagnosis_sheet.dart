import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Why does it not connect?" for one server: the layers checked in turn,
/// each with its result, and one sentence on what broke and what to do
/// (`DiagnoseNodeUseCase`).
///
/// Opened from the server's menu, and from the "check failed" toast after a
/// connect — the moment someone actually asks the question.
class DiagnosisSheet extends ConsumerStatefulWidget {
  /// Creates the sheet body for [node].
  const DiagnosisSheet({required this.node, super.key});

  /// The server to check.
  final ProxyNode node;

  /// Opens the sheet and starts the checks.
  static Future<void> show(BuildContext context, ProxyNode node) {
    return CommySheet.show<void>(
      context: context,
      title: Translations.of(context).diagnosis.title,
      builder: (context) => DiagnosisSheet(node: node),
    );
  }

  @override
  ConsumerState<DiagnosisSheet> createState() => _DiagnosisSheetState();
}

class _DiagnosisSheetState extends ConsumerState<DiagnosisSheet> {
  NodeDiagnosis? _diagnosis;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final run = ++_run;
    setState(() => _diagnosis = null);
    await ref.read(diagnoseNodeUseCaseProvider)(
      widget.node,
      onProgress: (progress) {
        if (mounted && run == _run) {
          setState(() => _diagnosis = progress);
        }
      },
    );
  }

  @override
  void dispose() {
    _run++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;
    final diagnosis = _diagnosis;
    final verdict = diagnosis?.verdict ?? DiagnosisVerdict.running;
    final (title, body, tone) = _verdictText(t, verdict);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            NodeLabel.of(widget.node).text,
            style: context.typography.caption.copyWith(
              color: colors.textTertiary,
            ),
          ),
          SizedBox(height: spacing.s3),
          for (final step in diagnosis?.steps ??
              <DiagnosisResult>[
                for (final step in DiagnoseNodeUseCase.stepsFor(widget.node))
                  DiagnosisResult(step, StepStatus.pending),
              ])
            if (step.status != StepStatus.skipped)
              _StepRow(
                result: step,
                // A layer above the one that broke is not judged: after the
                // verdict it is shown as not checked, not as still running.
                stopped: verdict != DiagnosisVerdict.running,
              ),
          SizedBox(height: spacing.s4),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: EdgeInsets.all(spacing.s4),
              decoration: BoxDecoration(
                color: switch (tone) {
                  CommyTone.connected => colors.statusConnectedWash,
                  CommyTone.error => colors.statusErrorWash,
                  _ => colors.bgOverlay,
                },
                borderRadius: context.radii.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.typography.title3.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (body != null) ...<Widget>[
                    SizedBox(height: spacing.s2),
                    Text(
                      body,
                      style: context.typography.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: spacing.s4),
          CommyButton(
            label: t.diagnosis.retry,
            variant: CommyButtonVariant.secondary,
            onPressed: verdict == DiagnosisVerdict.running
                ? null
                : () => unawaited(_start()),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  static (String, String?, CommyTone) _verdictText(
    Translations t,
    DiagnosisVerdict verdict,
  ) {
    final v = t.diagnosis.verdict;
    return switch (verdict) {
      DiagnosisVerdict.running => (v.running, null, CommyTone.neutral),
      DiagnosisVerdict.works => (v.works, v.worksBody, CommyTone.connected),
      DiagnosisVerdict.reachable => (
          v.reachable,
          v.reachableBody,
          CommyTone.neutral,
        ),
      DiagnosisVerdict.dnsFailed => (
          v.dnsFailed,
          v.dnsFailedBody,
          CommyTone.error,
        ),
      DiagnosisVerdict.portClosed => (
          v.portClosed,
          v.portClosedBody,
          CommyTone.error,
        ),
      DiagnosisVerdict.tlsFailed => (
          v.tlsFailed,
          v.tlsFailedBody,
          CommyTone.error,
        ),
      DiagnosisVerdict.certificateRefused => (
          v.certificateRefused,
          v.certificateRefusedBody,
          CommyTone.error,
        ),
      DiagnosisVerdict.protocolRefused => (
          v.protocolRefused,
          v.protocolRefusedBody,
          CommyTone.error,
        ),
    };
  }
}

/// One layer: its name, what it found, and a glyph for how it went.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.result, required this.stopped});

  final DiagnosisResult result;

  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final name = switch (result.step) {
      DiagnosisStep.dns => t.diagnosis.steps.dns,
      DiagnosisStep.tcp => t.diagnosis.steps.tcp,
      DiagnosisStep.tls => t.diagnosis.steps.tls,
      DiagnosisStep.proxy => t.diagnosis.steps.proxy,
    };
    final detail = result.detail;
    final shown = detail == null
        ? null
        : (int.tryParse(detail) == null ? detail : t.diagnosis.ms(ms: detail));

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CommySizes.minTapTarget),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: CommySizes.iconControl,
            child: switch (result.status) {
              StepStatus.pending when !stopped => const CommySpinner(),
              StepStatus.passed => Icon(
                  CommyIcons.success,
                  size: CommySizes.iconControl,
                  color: colors.statusConnected,
                ),
              StepStatus.failed => Icon(
                  CommyIcons.error,
                  size: CommySizes.iconControl,
                  color: colors.statusError,
                ),
              StepStatus.skipped || StepStatus.pending => Icon(
                  CommyIcons.info,
                  size: CommySizes.iconControl,
                  color: colors.textTertiary,
                ),
            },
          ),
          SizedBox(width: spacing.s3),
          Expanded(
            child: Text(
              name,
              style: context.typography.body.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          if (shown != null)
            Flexible(
              child: Text(
                shown,
                overflow: TextOverflow.ellipsis,
                style: context.typography.mono.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
