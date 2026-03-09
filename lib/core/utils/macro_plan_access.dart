import '../../domain/entities/macro_definition.dart';
import '../constants/app_constants.dart';

class MacroPlanAccess {
  const MacroPlanAccess._();

  static const Set<String> systemMacroIds = <String>{
    'macro_restart_stream',
    'macro_emergency_reset',
  };

  static bool isSystemMacro(MacroDefinition macro) {
    return isSystemMacroId(macro.id);
  }

  static bool isSystemMacroId(String macroId) {
    return systemMacroIds.contains(macroId);
  }

  static List<MacroDefinition> userMacros(List<MacroDefinition> macros) {
    return macros.where((macro) => !isSystemMacro(macro)).toList(growable: false);
  }

  static bool canCreateMacro({
    required bool isPremium,
    required List<MacroDefinition> macros,
  }) {
    if (isPremium) return true;
    return userMacros(macros).length < AppConstants.freeMacroLimit;
  }

  static bool canAddStep({
    required bool isPremium,
    required MacroDefinition macro,
  }) {
    if (isPremium) return true;
    return macro.steps.length < AppConstants.freeMacroActionLimit;
  }

  static bool isLockedForFreePlan({
    required bool isPremium,
    required List<MacroDefinition> macros,
    required MacroDefinition macro,
  }) {
    if (isPremium) return false;
    if (isSystemMacro(macro)) return true;

    final unlockedIds = userMacros(macros)
        .take(AppConstants.freeMacroLimit)
        .map((item) => item.id)
        .toSet();
    return !unlockedIds.contains(macro.id);
  }

  static List<MacroDefinition> accessibleMacros({
    required bool isPremium,
    required List<MacroDefinition> macros,
  }) {
    if (isPremium) return macros;
    return macros
        .where(
          (macro) => !isLockedForFreePlan(
            isPremium: isPremium,
            macros: macros,
            macro: macro,
          ),
        )
        .toList(growable: false);
  }
}
