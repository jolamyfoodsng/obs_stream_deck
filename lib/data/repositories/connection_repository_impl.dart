import '../../data/datasources/connection_local_datasource.dart';
import '../../domain/entities/obs_connection_config.dart';
import '../../domain/entities/saved_obs_connection.dart';
import '../../domain/repositories/connection_repository.dart';

class ConnectionRepositoryImpl implements ConnectionRepository {
  ConnectionRepositoryImpl(this._dataSource);

  final ConnectionLocalDataSource _dataSource;

  @override
  Future<ObsConnectionConfig?> loadConfig() => _dataSource.loadConfig();

  @override
  Future<void> saveConfig(ObsConnectionConfig config) =>
      _dataSource.saveConfig(config);

  @override
  Future<void> clearConfig() => _dataSource.clearConfig();

  @override
  Future<List<SavedObsConnection>> loadSavedConnections() =>
      _dataSource.loadSavedConnections();

  @override
  Future<void> saveSavedConnections(List<SavedObsConnection> connections) =>
      _dataSource.saveSavedConnections(connections);
}
