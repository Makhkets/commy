import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';

/// Storage of the application settings and of the current selection.
abstract interface class SettingsRepository {
  /// The settings, refreshed on every change.
  Stream<AppSettings> watch();

  /// The settings, once. Falls back to `AppSettings.defaults`.
  Future<Result<AppSettings, CommyFailure>> read();

  /// Replaces the settings wholesale.
  Future<Result<void, CommyFailure>> write(AppSettings settings);

  /// Id of the node the user last picked, or `null` when there is none.
  Future<Result<String?, CommyFailure>> readSelectedNodeId();

  /// Remembers the node the user picked. `null` clears the selection.
  Future<Result<void, CommyFailure>> writeSelectedNodeId(String? nodeId);
}
