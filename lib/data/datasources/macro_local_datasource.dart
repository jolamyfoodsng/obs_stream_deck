import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../data/models/macro_definition_model.dart';
import '../../domain/entities/macro_definition.dart';

class MacroLocalDataSource {
  MacroLocalDataSource(this._storageService);

  final LocalStorageService _storageService;

  Future<List<MacroDefinition>> loadMacros() async {
    final rawList = _storageService.getJsonList(StorageKeys.macros);
    return rawList.map(MacroDefinitionModel.fromJson).toList();
  }

  Future<void> saveMacros(List<MacroDefinition> macros) async {
    await _storageService.setJson(
      StorageKeys.macros,
      macros.map(MacroDefinitionModel.toJson).toList(),
    );
  }
}
