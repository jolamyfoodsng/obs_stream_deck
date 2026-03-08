import '../entities/button_action.dart';
import '../repositories/obs_repository.dart';

class ExecuteButtonActionUseCase {
  ExecuteButtonActionUseCase(this._obsRepository);

  final ObsRepository _obsRepository;

  Future<void> call(ButtonAction action) {
    return _obsRepository.executeAction(action);
  }
}
