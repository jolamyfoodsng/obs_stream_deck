import '../entities/macro_definition.dart';

abstract class MacroRepository {
  Future<List<MacroDefinition>> loadMacros();
  Future<void> saveMacros(List<MacroDefinition> macros);
}
