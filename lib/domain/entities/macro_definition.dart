enum MacroActionType {
  switchScene,
  setPreviewScene,
  showSource,
  hideSource,
  toggleSourceVisibility,
  mute,
  unmute,
  toggleMute,
  startStream,
  stopStream,
  startRecording,
  stopRecording,
  delay,
  runMacro,
}

class MacroAction {
  const MacroAction({
    required this.id,
    required this.type,
    this.targetId,
    this.targetName,
    this.delayMs,
  });

  final String id;
  final MacroActionType type;
  final String? targetId;
  final String? targetName;
  final int? delayMs;

  static const Object _notSpecified = Object();

  MacroAction copyWith({
    String? id,
    MacroActionType? type,
    Object? targetId = _notSpecified,
    Object? targetName = _notSpecified,
    Object? delayMs = _notSpecified,
  }) {
    return MacroAction(
      id: id ?? this.id,
      type: type ?? this.type,
      targetId: identical(targetId, _notSpecified)
          ? this.targetId
          : targetId as String?,
      targetName: identical(targetName, _notSpecified)
          ? this.targetName
          : targetName as String?,
      delayMs:
          identical(delayMs, _notSpecified) ? this.delayMs : delayMs as int?,
    );
  }
}

class MacroDefinition {
  const MacroDefinition({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.steps,
  });

  final String id;
  final String name;
  final String icon;
  final String colorHex;
  final List<MacroAction> steps;

  MacroDefinition copyWith({
    String? id,
    String? name,
    String? icon,
    String? colorHex,
    List<MacroAction>? steps,
  }) {
    return MacroDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      steps: steps ?? this.steps,
    );
  }
}

MacroActionType macroActionTypeFromName(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return MacroActionType.switchScene;
  }

  for (final type in MacroActionType.values) {
    if (type.name == raw) {
      return type;
    }
  }

  return MacroActionType.switchScene;
}
