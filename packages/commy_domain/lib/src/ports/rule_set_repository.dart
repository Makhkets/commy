import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/rule_set.dart';

/// The geoip and geosite files a rule can point at.
///
/// Exception **E-2** of docs/09-security-privacy.md lives behind this port,
/// and every clause of it is a constraint on the implementation and on the
/// caller: a download happens **only** on an explicit action, from a source
/// the user can change — their own mirror included — and the result is cached
/// on disk with the moment it arrived, so nothing has a reason to fetch it
/// again on its own.
///
/// Nothing here downloads by itself. A repository that refreshed a stale set
/// in the background would turn a sanctioned exception into traffic the user
/// did not ask for, which is rule R1.
abstract interface class RuleSetRepository {
  /// Everything currently on disk, newest write first to arrive.
  Stream<List<RuleSet>> watch();

  /// Everything currently on disk, once.
  Future<Result<List<RuleSet>, CommyFailure>> list();

  /// The directory the generated configuration points its `path` fields at.
  ///
  /// Created if it is missing: the core reads these files itself, and a path
  /// that does not exist is a configuration that fails to load.
  Future<Result<String, CommyFailure>> directory();

  /// Downloads one set from [from] and stores it under [tag].
  ///
  /// The caller has to have been asked. This method is the request going out.
  Future<Result<RuleSet, CommyFailure>> download({
    required String tag,
    required Uri from,
  });

  /// Removes one set from disk.
  Future<Result<void, CommyFailure>> delete(String tag);
}
