import 'package:obs_stream_deck/domain/entities/obs_connection_config.dart';
import 'package:obs_stream_deck/domain/entities/saved_obs_connection.dart';
import 'package:obs_stream_deck/domain/repositories/connection_repository.dart';

class FakeConnectionRepository implements ConnectionRepository {
  ObsConnectionConfig? config;
  List<SavedObsConnection> savedConnections;

  FakeConnectionRepository({
    this.config,
    List<SavedObsConnection>? savedConnections,
  }) : savedConnections = savedConnections ?? <SavedObsConnection>[];

  @override
  Future<void> clearConfig() async {
    config = null;
  }

  @override
  Future<ObsConnectionConfig?> loadConfig() async => config;

  @override
  Future<List<SavedObsConnection>> loadSavedConnections() async =>
      List<SavedObsConnection>.from(savedConnections);

  @override
  Future<void> saveConfig(ObsConnectionConfig config) async {
    this.config = config;
  }

  @override
  Future<void> saveSavedConnections(List<SavedObsConnection> connections) async {
    savedConnections = List<SavedObsConnection>.from(connections);
  }
}
