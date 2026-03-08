import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../data/models/controller_page_model.dart';
import '../../domain/entities/controller_page.dart';

class ControllerLocalDataSource {
  ControllerLocalDataSource(this._storageService);

  final LocalStorageService _storageService;

  Future<List<ControllerPage>> loadPages() async {
    final rawList = _storageService.getJsonList(StorageKeys.controllerPages);
    return rawList.map(ControllerPageModel.fromJson).toList();
  }

  Future<void> savePages(List<ControllerPage> pages) async {
    await _storageService.setJson(
      StorageKeys.controllerPages,
      pages.map(ControllerPageModel.toJson).toList(),
    );
  }
}
