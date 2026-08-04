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
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleSettings.useDeviceLocale();

  // The redactor is commy_data's, not commy_core's thinner default: the core
  // package cannot depend on commy_data, so this line is the only thing
  // keeping the app from running two different scrubbers (rule R3).
  final logger = AppLogger(redact: const LogRedactor().redact);
  final secureStore = FlutterSecureStore();
  final vault = SecretVault(store: secureStore);
  final opened = await openCommyDatabase(
    encryption: DatabaseEncryption(vault: vault),
  );
  if (opened.isDegraded) {
    // Said out loud rather than swallowed. docs/adr/0007 accepts an
    // unencrypted database file for 1.0; it does not accept pretending.
    logger.warn(
      'database file is not encrypted: ${opened.encryption.name}',
      tag: bootLogTag,
    );
  }

  final package = await PackageInfo.fromPlatform();

  runApp(
    ProviderScope(
      overrides: [
        appLoggerProvider.overrideWithValue(logger),
        secureStoreProvider.overrideWithValue(secureStore),
        databaseProvider.overrideWithValue(opened.database),
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
