import 'package:commy/app.dart';
import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_data/commy_data.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The composition root.
///
/// Everything asynchronous happens here, before the first frame, and is handed
/// to the widget tree as provider overrides. Nothing below this function opens
/// a database, touches a keystore or reads a plugin — which is what makes
/// every screen testable by swapping a handful of overrides instead of mocking
/// a platform.
///
/// Rule R2 lives on the two lines that build `SecretVault`: the keystore is
/// the only place credentials, subscription URLs and the generated
/// configuration are allowed to be.
///
/// **What is opened here is closed by the scope, not by this function.** The
/// database and the logger have to exist before the first provider is read —
/// one because opening it is asynchronous, the other because the line about an
/// unencrypted file is written before `runApp` — so they are built here and
/// then *given* to the graph with `ownedOverride`, which registers their
/// disposal. Handing them over with `overrideWithValue` would put them outside
/// the graph entirely: the provider body never runs, so nothing ever registers
/// an `onDispose`, and a container that was torn down would leave the database
/// open behind it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The redactor is commy_data's, not commy_core's thinner default: the core
  // package cannot depend on commy_data, so this line is the only thing
  // keeping the app from running two different scrubbers (rule R3).
  final logger = AppLogger(redact: const LogRedactor().redact);
  final secureStore = FlutterSecureStore();
  final vault = SecretVault(store: secureStore);

  // Everything the first frame waits for, started together (rule R11). The
  // three have nothing to do with one another — the locale, a keystore read
  // plus a database open, and a plugin call — and awaited one after another
  // the splash screen stayed up for their sum rather than for the slowest of
  // them, which is the database by a wide margin.
  final (_, opened, package) = await (
    LocaleSettings.useDeviceLocale(),
    openCommyDatabase(encryption: DatabaseEncryption(vault: vault)),
    PackageInfo.fromPlatform(),
  ).wait;
  if (opened.isDegraded) {
    // Said out loud rather than swallowed. docs/adr/0007 accepts an
    // unencrypted database file for 1.0; it does not accept pretending.
    logger.warn(
      'database file is not encrypted: ${opened.encryption.name}',
      tag: bootLogTag,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        ownedOverride(appLoggerProvider, logger, (it) => it.dispose()),
        secureStoreProvider.overrideWithValue(secureStore),
        ownedOverride(databaseProvider, opened.database, (it) => it.close()),
        databaseEncryptionProvider.overrideWithValue(opened.encryption),
        appInfoProvider.overrideWithValue(
          AppInfo(
            version: package.version,
            build: package.buildNumber,
            coreVersion: AppInfo.singBoxVersion,
          ),
        ),
      ],
      child: const CommyApp(),
    ),
  );
}

/// Tag on the log lines written before the first frame.
const String bootLogTag = 'boot';
