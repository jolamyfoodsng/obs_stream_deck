import '../entities/obs_connection_config.dart';
import '../repositories/connection_repository.dart';
import '../repositories/obs_repository.dart';

class ConnectToObsUseCase {
  ConnectToObsUseCase({
    required this.connectionRepository,
    required this.obsRepository,
  });

  final ConnectionRepository connectionRepository;
  final ObsRepository obsRepository;

  Future<void> call(ObsConnectionConfig config) async {
    if (config.rememberConnectionInfo) {
      await connectionRepository.saveConfig(config);
    } else {
      await connectionRepository.clearConfig();
    }
    await obsRepository.connect(config);
  }
}
