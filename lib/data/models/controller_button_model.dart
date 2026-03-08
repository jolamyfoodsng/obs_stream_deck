import '../../domain/entities/controller_button.dart';
import 'button_action_model.dart';

class ControllerButtonModel {
  const ControllerButtonModel._();

  static Map<String, dynamic> toJson(ControllerButton button) {
    return <String, dynamic>{
      'id': button.id,
      'label': button.label,
      'icon': button.icon,
      'activeColor': button.activeColor,
      'inactiveColor': button.inactiveColor,
      'category': button.category.name,
      'action': ButtonActionModel.toJson(button.action),
      'position': button.position,
      'isEnabled': button.isEnabled,
      'isActive': button.isActive,
      'longPressTrigger': button.longPressTrigger,
    };
  }

  static ControllerButton fromJson(Map<String, dynamic> json) {
    final activeColor =
        (json['activeColor'] ?? json['colorHex'] ?? '#137FEC') as String;
    final inactiveColor = (json['inactiveColor'] ?? '#64748B') as String;

    return ControllerButton(
      id: json['id'] as String,
      label: json['label'] as String,
      icon: json['icon'] as String,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      category: DeckButtonCategory.values.byName(json['category'] as String),
      action: ButtonActionModel.fromJson(
        (json['action'] as Map).cast<String, dynamic>(),
      ),
      position: (json['position'] as num).toInt(),
      isEnabled: json['isEnabled'] as bool? ?? true,
      isActive: json['isActive'] as bool? ?? false,
      longPressTrigger: json['longPressTrigger'] as bool? ??
          json['requiresLongPress'] as bool? ??
          false,
    );
  }
}
