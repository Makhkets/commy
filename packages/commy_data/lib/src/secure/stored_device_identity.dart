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
  /// `Windows`, `macOS`, `Linux`, spelled the way panels list them. It is the
  /// one field `dart:io` can answer, so it is the one that is not asked for.
  ///
  /// [describeDevice] supplies the other two, and it is a supplier rather than
  /// a pair of values because only the platform channel knows them and a
  /// channel call is asynchronous. Asked **once** and remembered: the model of
  /// a phone does not change while the app is open, and the version only does
  /// across a reboot that takes the process with it.
  StoredDeviceIdentity({
    required SecureStore store,
    required SettingsRepository settings,
    required IdGenerator ids,
    required this.platformName,
    Future<DeviceDescription?> Function()? describeDevice,
  })  : _store = store,
        _settings = settings,
        _ids = ids,
        _describeDevice = describeDevice;

  final SecureStore _store;
  final SettingsRepository _settings;
  final IdGenerator _ids;
  final Future<DeviceDescription?> Function()? _describeDevice;

  /// Name of the operating system, as panels spell it.
  final String platformName;

  /// The answer to [_describeDevice], once it has been asked.
  Future<DeviceDescription?>? _described;

  @override
  Future<Map<String, String>> subscriptionHeaders() async {
    try {
      final settings = await _settings.read();
      final allowed =
          (settings.valueOrNull ?? AppSettings.defaults).sendDeviceId;
      if (!allowed) {
        return const <String, String>{};
      }
      final described = await _describe();
      final version = described?.osVersion ?? '';
      final model = described?.model ?? '';
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

  /// The device description, asked for at most once.
  ///
  /// The future is cached rather than its value, so two refreshes racing at
  /// launch make one channel call between them instead of two.
  Future<DeviceDescription?> _describe() {
    final supplier = _describeDevice;
    if (supplier == null) {
      return Future<DeviceDescription?>.value();
    }
    return _described ??= supplier().catchError(
      // A platform that will not answer leaves the two optional headers out.
      // It must not turn a subscription refresh into a failure about
      // something the user never asked for.
      (Object _) => null,
    );
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
