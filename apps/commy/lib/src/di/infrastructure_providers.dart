/// The bottom layer of the composition root: everything the app needs that is
/// not a repository, a use case or a screen.
///
/// Two of these providers throw until overridden. That is deliberate. A
/// database and a keystore cannot be opened synchronously, so `main()` opens
/// them and hands them down through `ProviderScope(overrides: …)`; a provider
/// that quietly returned an in-memory stand-in would let a build ship with the
/// user's servers in RAM and nobody the wiser.
///
/// Everything else has a working default so that a widget test only overrides
/// what it actually cares about.
library;

import 'package:commy/src/platform/flutter_clipboard.dart';
import 'package:commy_config/commy_config.dart'
    show CommyLinkParser, ConfigPlatform;
import 'package:commy_core/commy_core.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thrown by the providers `main()` is required to override.
const String _mustOverride =
    'This provider has no default: the composition root in main.dart must '
    'override it. See lib/main.dart.';

/// The open Drift database.
///
/// Overridden in `main()` with the result of `openCommyDatabase`.
final databaseProvider = Provider<CommyDatabase>(
  (ref) => throw UnimplementedError('databaseProvider. $_mustOverride'),
);

/// Whether the database file itself could be encrypted on this build.
///
/// See docs/adr/0007-database-encryption.md: whole-file encryption is not in
/// 1.0, and the About screen says so out loud rather than implying otherwise.
final databaseEncryptionProvider = Provider<DatabaseEncryptionStatus>(
  (ref) => DatabaseEncryptionStatus.unavailable,
);

/// The platform keystore. Rule R2 lives here.
final secureStoreProvider = Provider<SecureStore>(
  (ref) => throw UnimplementedError('secureStoreProvider. $_mustOverride'),
);

/// The tunnel.
///
/// `CoreClientFactory` returns the Android client on Android and the fake
/// everywhere else, which is what makes every screen below runnable on a
/// laptop and testable without a device.
final coreClientProvider = Provider<CoreClient>((ref) {
  return CoreClientFactory.create(logger: ref.watch(appLoggerProvider));
});

/// Application and core version strings, read once at startup.
final appInfoProvider = Provider<AppInfo>((ref) => AppInfo.unknown);

/// System screens Commy can point at but not replace.
///
/// Only the VPN settings so far, and only because the kill-switch guarantee
/// belongs to Android rather than to us.
final systemSettingsProvider = Provider<SystemSettings>(
  (ref) => const SystemSettings(),
);

/// The single logger. Every `print` in this app would be a lint error; this is
/// the replacement (docs/09-security-privacy.md, rule R3).
///
/// The redactor is `commy_data`'s, injected here rather than left at
/// `commy_core`'s thinner default: the core package cannot depend on
/// `commy_data`, so without this line the app would run two different
/// scrubbers and drift.
final appLoggerProvider = Provider<AppLogger>((ref) {
  final logger = AppLogger(redact: const LogRedactor().redact);
  ref.onDispose(logger.dispose);
  return logger;
});

/// Which sing-box feature set the generated config may use.
final configPlatformProvider = Provider<ConfigPlatform>((ref) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => ConfigPlatform.android,
    TargetPlatform.iOS => ConfigPlatform.ios,
    TargetPlatform.macOS => ConfigPlatform.macos,
    TargetPlatform.windows => ConfigPlatform.windows,
    TargetPlatform.linux || TargetPlatform.fuchsia => ConfigPlatform.linux,
  };
});

/// Random identifiers for nodes, subscriptions and rules.
final idGeneratorProvider = Provider<IdGenerator>((ref) => RandomIdGenerator());

/// Reading and writing the system clipboard.
final clipboardProvider = Provider<ClipboardPort>(
  (ref) => const FlutterClipboard(),
);

/// Parses every link scheme and every subscription body shape we support.
final linkParserProvider = Provider<LinkParser>((ref) => CommyLinkParser());

/// The keystore wrapper the repositories write credentials through.
final secretVaultProvider = Provider<SecretVault>(
  (ref) => SecretVault(store: ref.watch(secureStoreProvider)),
);

/// The HTTP client. Only ever points at hosts the user typed (rule R1).
final httpClientProvider = Provider<CommyHttpClient>((ref) {
  final info = ref.watch(appInfoProvider);
  return CommyHttpClient(userAgent: CommyUserAgent.honest(info.version));
});

/// Version strings shown on the About screen.
@immutable
class AppInfo {
  /// Creates the descriptor.
  const AppInfo({
    required this.version,
    required this.build,
    required this.coreVersion,
  });

  /// What a build that never read `package_info_plus` reports.
  static const AppInfo unknown = AppInfo(
    version: 'dev',
    build: '0',
    coreVersion: singBoxVersion,
  );

  /// The sing-box release the Go module is pinned to.
  ///
  /// Rule R8: bumping the core is its own change, so this constant moves with
  /// `core/go.mod` and with nothing else.
  static const String singBoxVersion = '1.13.16';

  /// Public source of this build.
  static final Uri repository = Uri.parse('https://github.com/Makhkets/commy');

  /// Marketing version, e.g. `0.1.0`.
  final String version;

  /// Build number.
  final String build;

  /// The sing-box version inside the shipped core.
  final String coreVersion;

  /// `0.1.0 (1)`.
  String get fullVersion => '$version ($build)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppInfo &&
          other.version == version &&
          other.build == build &&
          other.coreVersion == coreVersion;

  @override
  int get hashCode => Object.hash(version, build, coreVersion);

  @override
  String toString() => 'AppInfo($fullVersion, sing-box $coreVersion)';
}
