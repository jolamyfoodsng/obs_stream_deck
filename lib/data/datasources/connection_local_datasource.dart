import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../data/models/obs_connection_config_model.dart';
import '../../data/models/saved_obs_connection_model.dart';
import '../../domain/entities/obs_connection_config.dart';
import '../../domain/entities/saved_obs_connection.dart';

class ConnectionLocalDataSource {
  ConnectionLocalDataSource(this._storageService);

  final LocalStorageService _storageService;

  Future<ObsConnectionConfig?> loadConfig() async {
    final json = _storageService.getJsonMap(StorageKeys.connectionConfig);
    if (json == null) return null;
    return ObsConnectionConfigModel.fromJson(json);
  }

  Future<void> saveConfig(ObsConnectionConfig config) async {
    await _storageService.setJson(
      StorageKeys.connectionConfig,
      ObsConnectionConfigModel.toJson(config),
    );
  }

  Future<void> clearConfig() async {
    await _storageService.remove(StorageKeys.connectionConfig);
  }

  Future<List<SavedObsConnection>> loadSavedConnections() async {
    final raw = _storageService.getJsonList(StorageKeys.savedObsConnections);
    return raw
        .map(SavedObsConnectionModel.fromJson)
        .where((connection) => connection.host.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveSavedConnections(
      List<SavedObsConnection> connections) async {
    await _storageService.setJson(
      StorageKeys.savedObsConnections,
      connections.map(SavedObsConnectionModel.toJson).toList(growable: false),
    );
  }
}
