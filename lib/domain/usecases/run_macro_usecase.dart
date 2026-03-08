import '../repositories/obs_repository.dart';

class RunMacroUseCase {
  RunMacroUseCase(this._obsRepository);

  final ObsRepository _obsRepository;

  Future<void> call(String macroId) {
    return _obsRepository.runMacro(macroId);
  }
}
