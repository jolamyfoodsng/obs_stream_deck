enum ButtonActionType {
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
  toggleStream,
  startRecording,
  stopRecording,
  pauseRecording,
  resumeRecording,
  toggleRecording,
  runMacro,
}

class ButtonAction {
  const ButtonAction({
    required this.type,
    this.targetId,
    this.targetName,
    this.metadata = const {},
  });

  final ButtonActionType type;
  final String? targetId;
  final String? targetName;
  final Map<String, dynamic> metadata;

  static const Object _notSpecified = Object();

  ButtonAction copyWith({
    ButtonActionType? type,
    Object? targetId = _notSpecified,
    Object? targetName = _notSpecified,
    Map<String, dynamic>? metadata,
  }) {
    return ButtonAction(
      type: type ?? this.type,
      targetId: identical(targetId, _notSpecified)
          ? this.targetId
          : targetId as String?,
      targetName: identical(targetName, _notSpecified)
          ? this.targetName
          : targetName as String?,
      metadata: metadata ?? this.metadata,
    );
  }
}

ButtonActionType buttonActionTypeFromName(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return ButtonActionType.switchScene;
  }

  for (final type in ButtonActionType.values) {
    if (type.name == raw) {
      return type;
    }
  }

  return ButtonActionType.switchScene;
}
