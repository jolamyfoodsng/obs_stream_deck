import 'dart:async';

import '../../core/services/obs_websocket_service.dart';
import '../../domain/entities/audio_source.dart';
import '../../domain/entities/button_action.dart';
import '../../domain/entities/macro_definition.dart';
import '../../domain/entities/obs_connection_config.dart';
import '../../domain/entities/obs_action_catalog.dart';
import '../../domain/entities/obs_runtime_state.dart';
import '../../domain/entities/scene_item.dart';
import '../../domain/entities/source_item.dart';
import '../../domain/repositories/macro_repository.dart';
import '../../domain/repositories/obs_repository.dart';

class ObsRepositoryImpl implements ObsRepository {
  ObsRepositoryImpl({
    required this.service,
    required this.macroRepository,
  });

  final ObsWebSocketService service;
  final MacroRepository macroRepository;

  @override
  Stream<ObsRuntimeState> watchState() => service.stateStream;

  @override
  ObsRuntimeState currentState() => service.currentState;

  @override
  Future<void> connect(ObsConnectionConfig config) => service.connect(config);

  @override
  Future<void> disconnect() => service.disconnect();

  @override
  Future<void> refreshState() => service.refreshState();

  @override
  Future<List<SceneItem>> fetchScenes() => service.fetchScenes();

  @override
  Future<List<AudioSource>> fetchAudioSources() => service.fetchAudioSources();

  @override
  Future<List<SourceItem>> fetchSources() => service.fetchSources();

  @override
  Future<String?> fetchSceneThumbnail(
    String sceneName, {
    int width = 192,
    int height = 108,
    int quality = 30,
  }) {
    return service.fetchSceneThumbnail(
      sceneName,
      width: width,
      height: height,
      quality: quality,
    );
  }

  @override
  Future<void> executeAction(ButtonAction action) =>
      service.executeAction(action);

  @override
  Future<void> runMacro(String macroId) async {
    final macros = await macroRepository.loadMacros();
    final macrosById = <String, MacroDefinition>{
      for (final macro in macros) macro.id: macro,
    };

    await _runMacroById(
      macroId: macroId,
      macrosById: macrosById,
      activeStack: <String>{},
    );
  }

  Future<void> _runMacroById({
    required String macroId,
    required Map<String, MacroDefinition> macrosById,
    required Set<String> activeStack,
  }) async {
    if (activeStack.contains(macroId)) {
      // Prevent infinite recursion when macros reference themselves.
      return;
    }

    final macro = macrosById[macroId];
    if (macro == null) return;

    activeStack.add(macroId);
    try {
      for (final step in macro.steps) {
        await _runMacroStep(
          step: step,
          macrosById: macrosById,
          activeStack: activeStack,
        );
      }
    } finally {
      activeStack.remove(macroId);
    }
  }

  Future<void> _runMacroStep({
    required MacroAction step,
    required Map<String, MacroDefinition> macrosById,
    required Set<String> activeStack,
  }) async {
    if (step.type == MacroActionType.delay) {
      final delayMs = step.delayMs ?? 500;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      return;
    }

    if (step.type == MacroActionType.runMacro) {
      final targetMacroId = step.targetId;
      if (targetMacroId == null || targetMacroId.isEmpty) return;
      await _runMacroById(
        macroId: targetMacroId,
        macrosById: macrosById,
        activeStack: activeStack,
      );
      return;
    }

    final mappedType = ObsActionCatalog.buttonTypeForMacroType(step.type);
    if (mappedType == null) return;

    await service.executeAction(
      ButtonAction(
        type: mappedType,
        targetId: step.targetId,
        targetName: step.targetName,
      ),
    );
  }
}
