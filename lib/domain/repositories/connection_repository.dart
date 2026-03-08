import '../entities/obs_connection_config.dart';
import '../entities/saved_obs_connection.dart';

abstract class ConnectionRepository {
  Future<ObsConnectionConfig?> loadConfig();
  Future<void> saveConfig(ObsConnectionConfig config);
  Future<void> clearConfig();
  Future<List<SavedObsConnection>> loadSavedConnections();
  Future<void> saveSavedConnections(List<SavedObsConnection> connections);
}
