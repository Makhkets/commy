import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/components/atoms/commy_badge.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/util/byte_format.dart';
import 'package:commy_ui/src/util/duration_format.dart';
import 'package:flutter/material.dart';

/// One live connection the core is carrying.
///
/// This row exists to answer one question — "why is this site going around
/// the proxy?" — so the rule that matched and the outbound it was handed to
/// are given the same weight as the host itself. A connection list that shows
/// only hosts and byte counts answers nothing.
///
/// Volumes and the age of the connection are monospace with tabular figures:
/// the numbers change several times a second and the row must not twitch.
///
/// The metadata line flows rather than clips. Five facts in one row survive
/// the default type size and nothing else, so at a large system font the
/// transport, the rule and the two volumes drop onto further lines instead of
/// running off the edge — the screen has to hold together at 200%.
class ConnectionRow extends StatelessWidget {
  /// Creates a connection row.
  const ConnectionRow({
    required this.connection,
    required this.age,
    this.onTap,
    super.key,
  });

  /// What sits between the rule and the outbound it selected.
  static const String separator = ' · ';

  /// The connection, as the core reports it.
  final ConnectionInfo connection;

  /// How long it has been open.
  ///
  /// Passed in rather than computed from `DateTime.now()` here: the screen
  /// owns the clock, and a widget that reads the wall clock during build
  /// cannot be tested or golden-tested.
  final Duration age;

  /// Tap handler, for the connection detail.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CommySizes.minTapTarget),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.s4,
          vertical: spacing.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    connection.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: spacing.s2),
                Text(
                  CommyDurationFormat.clock(age),
                  maxLines: 1,
                  style: type.monoSmall.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
            SizedBox(height: spacing.s1),
            LayoutBuilder(
              builder: (context, constraints) {
                final limit = BoxConstraints(maxWidth: constraints.maxWidth);
                return Wrap(
                  spacing: spacing.s2,
                  runSpacing: spacing.s1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    CommyBadge(label: connection.network),
                    ConstrainedBox(
                      constraints: limit,
                      child: Text(
                        '${connection.rule}$separator${connection.outbound}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: limit,
                      child: _Volume(
                        icon: CommyIcons.arrowUp,
                        value: CommyByteFormat.bytes(connection.uploadTotal),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: limit,
                      child: _Volume(
                        icon: CommyIcons.arrowDown,
                        value: CommyByteFormat.bytes(
                          connection.downloadTotal,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      child: Material(
        color: colors.bgSurface,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: CommySizes.iconInline, color: colors.textTertiary),
        SizedBox(width: context.spacing.s1),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.monoSmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
