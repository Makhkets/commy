import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saving, switching, renaming and removing routing profiles (D10), and
/// taking one in from a shared link (D11).
///
/// Every change goes through `RoutingRepository.writeProfiles`, which writes
/// the list and the live policy in one transaction. The live-reload provider
/// sees the policy change like any edit on the routing screen and hands it to
/// a running core without a reconnect.
final routingProfilesControllerProvider =
    NotifierProvider<RoutingProfilesController, CommyFailure?>(
  RoutingProfilesController.new,
);

/// Holds the last failure, for the screen to say.
class RoutingProfilesController extends Notifier<CommyFailure?> {
  @override
  CommyFailure? build() => null;

  /// Saves the routing in force as a new profile named [name] and makes it
  /// the active one. [currentName] names the setup kept the first time.
  Future<bool> saveAs(String name, {required String currentName}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final read = await _read();
    if (read == null) {
      return false;
    }
    final ids = ref.read(idGeneratorProvider);
    return _write(
      read.profiles.saveAs(
        live: read.live,
        name: trimmed,
        id: ids.newId(),
        currentName: currentName,
        currentId: ids.newId(),
      ),
    );
  }

  /// Makes [id] the active profile and its routing the one in force.
  Future<bool> switchTo(String id) async {
    final read = await _read();
    final switched = read?.profiles.switchTo(id, live: read.live);
    if (switched == null) {
      return false;
    }
    return _write(switched.profiles, live: switched.live);
  }

  /// Renames [id].
  Future<bool> rename(String id, String name) async {
    final read = await _read();
    if (read == null) {
      return false;
    }
    return _write(read.profiles.rename(id, name));
  }

  /// Removes [id]; refused for the active and the last profile.
  Future<bool> remove(String id) async {
    final read = await _read();
    final left = read?.profiles.remove(id);
    if (left == null) {
      return false;
    }
    return _write(left);
  }

  /// Adds [profile] — one from a shared link — and switches to it.
  Future<bool> addAndSwitch(
    RoutingProfile profile, {
    required String currentName,
  }) async {
    final read = await _read();
    if (read == null) {
      return false;
    }
    final added = read.profiles.add(
      live: read.live,
      profile: profile,
      currentName: currentName,
      currentId: ref.read(idGeneratorProvider).newId(),
    );
    return _write(added, live: profile.policy);
  }

  Future<({RoutingProfiles profiles, RoutingPolicy live})?> _read() async {
    final repository = ref.read(routingRepositoryProvider);
    final profiles = await repository.readProfiles();
    final live = await repository.read();
    final failure = profiles.failureOrNull ?? live.failureOrNull;
    if (failure != null) {
      state = failure;
      return null;
    }
    return (profiles: profiles.valueOrNull!, live: live.valueOrNull!);
  }

  Future<bool> _write(RoutingProfiles profiles, {RoutingPolicy? live}) async {
    final result = await ref
        .read(routingRepositoryProvider)
        .writeProfiles(profiles, live: live);
    if (!ref.mounted) {
      return false;
    }
    state = result.failureOrNull;
    if (state != null) {
      ref.read(appLoggerProvider).warn(
            'routing profiles not written: ${state!.code}',
            tag: 'routing',
          );
    }
    return state == null;
  }
}
