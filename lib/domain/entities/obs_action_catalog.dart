import 'button_action.dart';
import 'macro_definition.dart';

enum ObsActionCode {
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
  delay,
}

enum ObsActionTargetKind {
  none,
  scene,
  source,
  audioSource,
  macro,
  delayMs,
}

class ObsActionDefinition {
  const ObsActionDefinition({
    required this.code,
    required this.label,
    required this.targetKind,
    this.requiresStudioMode = false,
    this.buttonSupported = true,
    this.macroSupported = true,
    this.optionalInMacroEditor = false,
  });

  final ObsActionCode code;
  final String label;
  final ObsActionTargetKind targetKind;
  final bool requiresStudioMode;
  final bool buttonSupported;
  final bool macroSupported;
  final bool optionalInMacroEditor;

  bool get requiresTarget {
    switch (targetKind) {
      case ObsActionTargetKind.none:
      case ObsActionTargetKind.delayMs:
        return false;
      case ObsActionTargetKind.scene:
      case ObsActionTargetKind.source:
      case ObsActionTargetKind.audioSource:
      case ObsActionTargetKind.macro:
        return true;
    }
  }
}

class ObsActionCatalog {
  const ObsActionCatalog._();

  static const List<ObsActionDefinition> _definitions = <ObsActionDefinition>[
    ObsActionDefinition(
      code: ObsActionCode.switchScene,
      label: 'Switch Scene',
      targetKind: ObsActionTargetKind.scene,
    ),
    ObsActionDefinition(
      code: ObsActionCode.setPreviewScene,
      label: 'Set Preview Scene',
      targetKind: ObsActionTargetKind.scene,
      requiresStudioMode: true,
    ),
    ObsActionDefinition(
      code: ObsActionCode.showSource,
      label: 'Show Source',
      targetKind: ObsActionTargetKind.source,
    ),
    ObsActionDefinition(
      code: ObsActionCode.hideSource,
      label: 'Hide Source',
      targetKind: ObsActionTargetKind.source,
    ),
    ObsActionDefinition(
      code: ObsActionCode.toggleSourceVisibility,
      label: 'Toggle Source Visibility',
      targetKind: ObsActionTargetKind.source,
    ),
    ObsActionDefinition(
      code: ObsActionCode.mute,
      label: 'Mute',
      targetKind: ObsActionTargetKind.audioSource,
    ),
    ObsActionDefinition(
      code: ObsActionCode.unmute,
      label: 'Unmute',
      targetKind: ObsActionTargetKind.audioSource,
    ),
    ObsActionDefinition(
      code: ObsActionCode.toggleMute,
      label: 'Toggle Mute',
      targetKind: ObsActionTargetKind.audioSource,
    ),
    ObsActionDefinition(
      code: ObsActionCode.startStream,
      label: 'Start Stream',
      targetKind: ObsActionTargetKind.none,
    ),
    ObsActionDefinition(
      code: ObsActionCode.stopStream,
      label: 'Stop Stream',
      targetKind: ObsActionTargetKind.none,
    ),
    ObsActionDefinition(
      code: ObsActionCode.toggleStream,
      label: 'Toggle Stream',
      targetKind: ObsActionTargetKind.none,
    ),
    ObsActionDefinition(
      code: ObsActionCode.startRecording,
      label: 'Start Recording',
      targetKind: ObsActionTargetKind.none,
    ),
    ObsActionDefinition(
      code: ObsActionCode.stopRecording,
      label: 'Stop Recording',
      targetKind: ObsActionTargetKind.none,
    ),
    ObsActionDefinition(
      code: ObsActionCode.pauseRecording,
      label: 'Pause Recording',
      targetKind: ObsActionTargetKind.none,
      macroSupported: false,
    ),
    ObsActionDefinition(
      code: ObsActionCode.resumeRecording,
      label: 'Resume Recording',
      targetKind: ObsActionTargetKind.none,
      macroSupported: false,
    ),
    ObsActionDefinition(
      code: ObsActionCode.toggleRecording,
      label: 'Toggle Recording',
      targetKind: ObsActionTargetKind.none,
      macroSupported: false,
    ),
    ObsActionDefinition(
      code: ObsActionCode.runMacro,
      label: 'Run Macro',
      targetKind: ObsActionTargetKind.macro,
      optionalInMacroEditor: true,
    ),
    ObsActionDefinition(
      code: ObsActionCode.delay,
      label: 'Delay',
      targetKind: ObsActionTargetKind.delayMs,
      buttonSupported: false,
    ),
  ];

  static const Map<ButtonActionType, ObsActionCode> _buttonToCode =
      <ButtonActionType, ObsActionCode>{
    ButtonActionType.switchScene: ObsActionCode.switchScene,
    ButtonActionType.setPreviewScene: ObsActionCode.setPreviewScene,
    ButtonActionType.showSource: ObsActionCode.showSource,
    ButtonActionType.hideSource: ObsActionCode.hideSource,
    ButtonActionType.toggleSourceVisibility:
        ObsActionCode.toggleSourceVisibility,
    ButtonActionType.mute: ObsActionCode.mute,
    ButtonActionType.unmute: ObsActionCode.unmute,
    ButtonActionType.toggleMute: ObsActionCode.toggleMute,
    ButtonActionType.startStream: ObsActionCode.startStream,
    ButtonActionType.stopStream: ObsActionCode.stopStream,
    ButtonActionType.toggleStream: ObsActionCode.toggleStream,
    ButtonActionType.startRecording: ObsActionCode.startRecording,
    ButtonActionType.stopRecording: ObsActionCode.stopRecording,
    ButtonActionType.pauseRecording: ObsActionCode.pauseRecording,
    ButtonActionType.resumeRecording: ObsActionCode.resumeRecording,
    ButtonActionType.toggleRecording: ObsActionCode.toggleRecording,
    ButtonActionType.runMacro: ObsActionCode.runMacro,
  };

  static const Map<MacroActionType, ObsActionCode> _macroToCode =
      <MacroActionType, ObsActionCode>{
    MacroActionType.switchScene: ObsActionCode.switchScene,
    MacroActionType.setPreviewScene: ObsActionCode.setPreviewScene,
    MacroActionType.showSource: ObsActionCode.showSource,
    MacroActionType.hideSource: ObsActionCode.hideSource,
    MacroActionType.toggleSourceVisibility:
        ObsActionCode.toggleSourceVisibility,
    MacroActionType.mute: ObsActionCode.mute,
    MacroActionType.unmute: ObsActionCode.unmute,
    MacroActionType.toggleMute: ObsActionCode.toggleMute,
    MacroActionType.startStream: ObsActionCode.startStream,
    MacroActionType.stopStream: ObsActionCode.stopStream,
    MacroActionType.startRecording: ObsActionCode.startRecording,
    MacroActionType.stopRecording: ObsActionCode.stopRecording,
    MacroActionType.delay: ObsActionCode.delay,
    MacroActionType.runMacro: ObsActionCode.runMacro,
  };

  static final Map<ObsActionCode, ObsActionDefinition> _definitionByCode =
      <ObsActionCode, ObsActionDefinition>{
    for (final definition in _definitions) definition.code: definition,
  };

  static final Map<ObsActionCode, ButtonActionType> _codeToButton =
      <ObsActionCode, ButtonActionType>{
    for (final entry in _buttonToCode.entries) entry.value: entry.key,
  };

  static final Map<ObsActionCode, MacroActionType> _codeToMacro =
      <ObsActionCode, MacroActionType>{
    for (final entry in _macroToCode.entries) entry.value: entry.key,
  };

  static ObsActionCode codeForButtonType(ButtonActionType type) {
    return _buttonToCode[type]!;
  }

  static ObsActionCode codeForMacroType(MacroActionType type) {
    return _macroToCode[type]!;
  }

  static ObsActionDefinition definitionForCode(ObsActionCode code) {
    return _definitionByCode[code]!;
  }

  static ObsActionDefinition definitionForButtonType(ButtonActionType type) {
    return definitionForCode(codeForButtonType(type));
  }

  static ObsActionDefinition definitionForMacroType(MacroActionType type) {
    return definitionForCode(codeForMacroType(type));
  }

  static List<ButtonActionType> buttonActions() {
    return ButtonActionType.values
        .where((type) => definitionForButtonType(type).buttonSupported)
        .toList(growable: false);
  }

  static List<MacroActionType> macroActions({
    bool includeOptional = false,
  }) {
    return MacroActionType.values.where((type) {
      final definition = definitionForMacroType(type);
      if (!definition.macroSupported) return false;
      if (!includeOptional && definition.optionalInMacroEditor) return false;
      return true;
    }).toList(growable: false);
  }

  static ButtonActionType? buttonTypeForMacroType(MacroActionType type) {
    final code = codeForMacroType(type);
    return _codeToButton[code];
  }

  static MacroActionType? macroTypeForButtonType(ButtonActionType type) {
    final code = codeForButtonType(type);
    return _codeToMacro[code];
  }
}
