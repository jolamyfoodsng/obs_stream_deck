import '../../domain/entities/button_action.dart';

class VolunteerModePolicy {
  const VolunteerModePolicy._();

  static bool isRestrictedButtonAction(ButtonActionType type) {
    switch (type) {
      case ButtonActionType.stopStream:
      case ButtonActionType.toggleStream:
      case ButtonActionType.stopRecording:
      case ButtonActionType.pauseRecording:
      case ButtonActionType.resumeRecording:
      case ButtonActionType.toggleRecording:
      case ButtonActionType.runMacro:
        return true;
      case ButtonActionType.switchScene:
      case ButtonActionType.setPreviewScene:
      case ButtonActionType.showSource:
      case ButtonActionType.hideSource:
      case ButtonActionType.toggleSourceVisibility:
      case ButtonActionType.mute:
      case ButtonActionType.unmute:
      case ButtonActionType.toggleMute:
      case ButtonActionType.startStream:
      case ButtonActionType.startRecording:
        return false;
    }
  }
}
