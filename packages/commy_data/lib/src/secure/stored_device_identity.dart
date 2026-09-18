import 'package:commy_data/src/secure/secret_keys.dart';
import 'package:commy_data/src/secure/secure_store.dart';
import 'package:commy_domain/commy_domain.dart';

/// [DeviceIdentity] kept in the encrypted store.
///
/// The identifier is made on first need rather than at install: a user who
/// never adds a subscription, or who switches the identifier off before adding
/// one, never has one at all.
class StoredDeviceIdentity implements DeviceIdentity {
  /// Creates the identity.
  ///
  /// [platformName] is what `x-device-os` carries — `Android`, `iOS`,
  /// `Windows`, `macOS`, `Linux`, spelled the way panels list them.
  /// [platformVersion] and [deviceModel] are sent only when known; a header
  /// with a guess in it is worse than a header that is absent.
  const StoredDeviceIdentity({
    required SecureStore store,
    required SettingsRepository settings,
    required IdGenerator ids,
    required this.platformName,
    this.platformVersion,
    this.deviceModel,
  })  : _store = store,
        _settings = settings,
        _ids = ids;

  final SecureStore _store;
  final SettingsRepository _settings;
  final IdGenerator _ids;

  /// Name of the operating system, as panels spell it.
  final String platformName;

  /// Version of the operating system, when it could be read.
  final String? platformVersion;

  /// Model of the device, when it could be read.
  final String? deviceModel;

  @override
  Future<Map<String, String>> subscriptionHeaders() async {
    try {
      final settings = await _settings.read();
      final allowed =
          (settings.valueOrNull ?? AppSettings.defaults).sendDeviceId;
      if (!allowed) {
        return const <String, String>{};
      }
      final version = platformVersion?.trim() ?? '';
      final model = deviceModel?.trim() ?? '';
      return <String, String>{
        DeviceIdentity.hwidHeader: await _readOrCreate(),
        DeviceIdentity.osHeader: platformName,
        if (version.isNotEmpty) DeviceIdentity.osVersionHeader: version,
        if (model.isNotEmpty) DeviceIdentity.modelHeader: model,
      };
    } on Object {
      // The identifier is optional to us even where it is mandatory to a
      // panel. A keystore that will not answer must not turn "refresh the
      // subscription" into a failure about something the user never asked for.
      return const <String, String>{};
    }
  }

  @override
  Future<Result<void, CommyFailure>> reset() async {
    try {
      await _store.delete(SecretKeys.deviceId);
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error) {
      return Err<void, CommyFailure>(StorageFailure(error));
    }
  }

  Future<String> _readOrCreate() async {
    final stored = (await _store.read(SecretKeys.deviceId))?.trim() ?? '';
    if (stored.isNotEmpty) {
      return stored;
    }
    final created = _ids.newId();
    await _store.write(SecretKeys.deviceId, created);
    return created;
  }
}
