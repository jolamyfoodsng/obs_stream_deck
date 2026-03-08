import 'button_action.dart';

enum DeckButtonCategory {
  scene,
  audio,
  source,
  stream,
  recording,
  macro,
  utility,
}

class ControllerButton {
  const ControllerButton({
    required this.id,
    required this.label,
    required this.icon,
    String? activeColor,
    String? inactiveColor,
    required this.category,
    required this.action,
    required this.position,
    this.isEnabled = true,
    this.isActive = false,
    bool? longPressTrigger,
    @Deprecated('Use activeColor instead') String? colorHex,
    @Deprecated('Use longPressTrigger instead') bool? requiresLongPress,
  })  : activeColor = activeColor ?? colorHex ?? '#137FEC',
        inactiveColor = inactiveColor ?? '#64748B',
        longPressTrigger = longPressTrigger ?? requiresLongPress ?? false;

  final String id;
  final String label;
  final String icon;
  final String activeColor;
  final String inactiveColor;
  final DeckButtonCategory category;
  final ButtonAction action;
  final int position;
  final bool isEnabled;
  final bool isActive;
  final bool longPressTrigger;

  ControllerButton copyWith({
    String? id,
    String? label,
    String? icon,
    String? activeColor,
    String? inactiveColor,
    DeckButtonCategory? category,
    ButtonAction? action,
    int? position,
    bool? isEnabled,
    bool? isActive,
    bool? longPressTrigger,
  }) {
    return ControllerButton(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      activeColor: activeColor ?? this.activeColor,
      inactiveColor: inactiveColor ?? this.inactiveColor,
      category: category ?? this.category,
      action: action ?? this.action,
      position: position ?? this.position,
      isEnabled: isEnabled ?? this.isEnabled,
      isActive: isActive ?? this.isActive,
      longPressTrigger: longPressTrigger ?? this.longPressTrigger,
    );
  }

  @Deprecated('Use activeColor instead')
  String get colorHex => activeColor;

  @Deprecated('Use longPressTrigger instead')
  bool get requiresLongPress => longPressTrigger;
}
