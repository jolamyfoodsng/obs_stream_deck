import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/data/models/button_action_model.dart';
import 'package:obs_stream_deck/data/models/macro_definition_model.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/macro_definition.dart';
import 'package:obs_stream_deck/domain/entities/obs_action_catalog.dart';

void main() {
  test('button action catalog includes full OBS controller action set', () {
    final actions = ObsActionCatalog.buttonActions();

    expect(actions, contains(ButtonActionType.switchScene));
    expect(actions, contains(ButtonActionType.setPreviewScene));
    expect(actions, contains(ButtonActionType.showSource));
    expect(actions, contains(ButtonActionType.hideSource));
    expect(actions, contains(ButtonActionType.toggleSourceVisibility));
    expect(actions, contains(ButtonActionType.mute));
    expect(actions, contains(ButtonActionType.unmute));
    expect(actions, contains(ButtonActionType.toggleMute));
    expect(actions, contains(ButtonActionType.startStream));
    expect(actions, contains(ButtonActionType.stopStream));
    expect(actions, contains(ButtonActionType.toggleStream));
    expect(actions, contains(ButtonActionType.startRecording));
    expect(actions, contains(ButtonActionType.stopRecording));
    expect(actions, contains(ButtonActionType.pauseRecording));
    expect(actions, contains(ButtonActionType.resumeRecording));
    expect(actions, contains(ButtonActionType.toggleRecording));
    expect(actions, contains(ButtonActionType.runMacro));
  });

  test('macro action catalog includes supported macro actions', () {
    final actions = ObsActionCatalog.macroActions();

    expect(actions, contains(MacroActionType.switchScene));
    expect(actions, contains(MacroActionType.setPreviewScene));
    expect(actions, contains(MacroActionType.showSource));
    expect(actions, contains(MacroActionType.hideSource));
    expect(actions, contains(MacroActionType.toggleSourceVisibility));
    expect(actions, contains(MacroActionType.mute));
    expect(actions, contains(MacroActionType.unmute));
    expect(actions, contains(MacroActionType.toggleMute));
    expect(actions, contains(MacroActionType.startStream));
    expect(actions, contains(MacroActionType.stopStream));
    expect(actions, contains(MacroActionType.startRecording));
    expect(actions, contains(MacroActionType.stopRecording));
    expect(actions, contains(MacroActionType.delay));
    expect(actions, isNot(contains(MacroActionType.runMacro)));
  });

  test('button action model round-trips targetName', () {
    const action = ButtonAction(
      type: ButtonActionType.switchScene,
      targetId: 'scene_main',
      targetName: 'Main Scene',
    );

    final json = ButtonActionModel.toJson(action);
    final decoded = ButtonActionModel.fromJson(json);

    expect(decoded.type, ButtonActionType.switchScene);
    expect(decoded.targetId, 'scene_main');
    expect(decoded.targetName, 'Main Scene');
  });

  test('macro definition model round-trips step targetName', () {
    const macro = MacroDefinition(
      id: 'macro_1',
      name: 'Test Macro',
      icon: 'bolt',
      colorHex: '#000000',
      steps: <MacroAction>[
        MacroAction(
          id: 'step_1',
          type: MacroActionType.showSource,
          targetId: 'scene::item',
          targetName: 'Overlay (Gameplay)',
        ),
      ],
    );

    final json = MacroDefinitionModel.toJson(macro);
    final decoded = MacroDefinitionModel.fromJson(json);

    expect(decoded.steps.first.type, MacroActionType.showSource);
    expect(decoded.steps.first.targetId, 'scene::item');
    expect(decoded.steps.first.targetName, 'Overlay (Gameplay)');
  });
}
