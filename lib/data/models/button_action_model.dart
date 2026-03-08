import '../../domain/entities/button_action.dart';

class ButtonActionModel {
  const ButtonActionModel._();

  static Map<String, dynamic> toJson(ButtonAction action) {
    return <String, dynamic>{
      'type': action.type.name,
      'targetId': action.targetId,
      'targetName': action.targetName,
      'metadata': action.metadata,
    };
  }

  static ButtonAction fromJson(Map<String, dynamic> json) {
    return ButtonAction(
      type: buttonActionTypeFromName(json['type'] as String?),
      targetId: json['targetId'] as String?,
      targetName: json['targetName'] as String?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
  }
}
