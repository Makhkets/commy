/// The design system of Commy: tokens, themes, atoms, molecules, organisms
/// and the three adaptive shells.
///
/// Everything a screen is allowed to use is exported here. `lib/src/` is
/// private by convention — an import that reaches into it is a bug, because
/// it is the only thing standing between us and a widget that draws its own
/// colour (rule R4).
///
/// **Reading a token.** Never construct one; ask the current theme:
///
/// ```dart
/// Container(
///   color: context.colors.bgSurface,
///   padding: EdgeInsets.all(context.spacing.s4),
/// );
/// ```
///
/// **Strings.** This package holds none. Every label, hint and accessible
/// name arrives already translated from `slang`, which lives in the app.
///
/// **One name to watch.** `commy_domain` exports a `LogLine` entity; the
/// widget that draws it is called `LogLineView`, so that an app importing both
/// packages never has to prefix either. Nothing else in this library collides
/// with the domain, with Flutter, or with Material.
library;

export 'src/components/atoms/commy_badge.dart';
export 'src/components/atoms/commy_button.dart';
export 'src/components/atoms/commy_button_variant.dart';
export 'src/components/atoms/commy_checkbox.dart';
export 'src/components/atoms/commy_chip.dart';
export 'src/components/atoms/commy_divider.dart';
export 'src/components/atoms/commy_icon_button.dart';
export 'src/components/atoms/commy_radio.dart';
export 'src/components/atoms/commy_skeleton.dart';
export 'src/components/atoms/commy_spinner.dart';
export 'src/components/atoms/commy_switch.dart';
export 'src/components/atoms/commy_text_field.dart';
export 'src/components/commy_icons.dart';
export 'src/components/commy_tone.dart';
export 'src/components/country_flag.dart';
export 'src/components/molecules/empty_state.dart';
export 'src/components/molecules/error_banner.dart';
export 'src/components/molecules/latency_badge.dart';
export 'src/components/molecules/quota_bar.dart';
export 'src/components/molecules/search_field.dart';
export 'src/components/molecules/segmented_control.dart';
export 'src/components/molecules/segmented_control_item.dart';
export 'src/components/molecules/status_pill.dart';
export 'src/components/molecules/toast.dart';
export 'src/components/molecules/traffic_meter.dart';
export 'src/components/organisms/check_button.dart';
export 'src/components/organisms/connect_button.dart';
export 'src/components/organisms/connect_state.dart';
export 'src/components/organisms/connection_row.dart';
export 'src/components/organisms/group_header.dart';
export 'src/components/organisms/log_line.dart';
export 'src/components/organisms/metrics_strip.dart';
export 'src/components/organisms/node_tile.dart';
export 'src/components/organisms/rule_row.dart';
export 'src/components/organisms/selected_node.dart';
export 'src/components/organisms/subscription_card.dart';
export 'src/components/organisms/traffic_chart.dart';
export 'src/components/shells/adaptive_scaffold.dart';
export 'src/components/shells/commy_app_bar.dart';
export 'src/components/shells/commy_destination.dart';
export 'src/components/shells/commy_sheet.dart';
export 'src/components/shells/desktop_shell.dart';
export 'src/components/shells/mobile_shell.dart';
export 'src/components/shells/tablet_shell.dart';
export 'src/theme/context_extensions.dart';
export 'src/theme/theme.dart';
export 'src/tokens/breakpoints.dart';
export 'src/tokens/colors.dart';
export 'src/tokens/connect_tokens.dart';
export 'src/tokens/elevation.dart';
export 'src/tokens/flag_palette.dart';
export 'src/tokens/fonts.dart';
export 'src/tokens/layout_size.dart';
export 'src/tokens/motion.dart';
export 'src/tokens/power_glyph.dart';
export 'src/tokens/radii.dart';
export 'src/tokens/sizes.dart';
export 'src/tokens/spacing.dart';
export 'src/tokens/spring_curve.dart';
export 'src/tokens/thresholds.dart';
export 'src/tokens/typography.dart';
export 'src/util/byte_format.dart';
export 'src/util/duration_format.dart';
