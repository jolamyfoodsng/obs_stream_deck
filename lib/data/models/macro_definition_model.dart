import '../../domain/entities/macro_definition.dart';

class MacroDefinitionModel {
  const MacroDefinitionModel._();

  static Map<String, dynamic> toJson(MacroDefinition macro) {
    return <String, dynamic>{
      'id': macro.id,
      'name': macro.name,
      'icon': macro.icon,
      'colorHex': macro.colorHex,
      'steps': macro.steps
          .map(
            (step) => <String, dynamic>{
              'id': step.id,
              'type': step.type.name,
              'targetId': step.targetId,
              'targetName': step.targetName,
              'delayMs': step.delayMs,
            },
          )
          .toList(),
    };
  }

  static MacroDefinition fromJson(Map<String, dynamic> json) {
    return MacroDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      colorHex: json['colorHex'] as String,
      steps: ((json['steps'] as List?) ?? <dynamic>[])
          .map(
            (entry) => MacroAction(
              id: (entry as Map)['id'] as String,
              type: macroActionTypeFromName(entry['type'] as String?),
              targetId: entry['targetId'] as String?,
              targetName: entry['targetName'] as String?,
              delayMs: (entry['delayMs'] as num?)?.toInt(),
            ),
          )
          .toList(),
    );
  }
}
