import 'package:obs_stream_deck/domain/entities/macro_definition.dart';
import 'package:obs_stream_deck/domain/repositories/macro_repository.dart';

class FakeMacroRepository implements MacroRepository {
  List<MacroDefinition> macros;

  FakeMacroRepository({List<MacroDefinition>? macros})
      : macros = macros ?? <MacroDefinition>[];

  @override
  Future<List<MacroDefinition>> loadMacros() async =>
      List<MacroDefinition>.from(macros);

  @override
  Future<void> saveMacros(List<MacroDefinition> macros) async {
    this.macros = List<MacroDefinition>.from(macros);
  }
}
