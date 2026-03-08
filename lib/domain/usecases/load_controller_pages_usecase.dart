import '../entities/controller_page.dart';
import '../repositories/controller_repository.dart';

class LoadControllerPagesUseCase {
  LoadControllerPagesUseCase(this._controllerRepository);

  final ControllerRepository _controllerRepository;

  Future<List<ControllerPage>> call() {
    return _controllerRepository.loadPages();
  }
}
