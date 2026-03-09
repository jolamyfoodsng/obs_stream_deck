import 'dart:async';

import 'package:obs_stream_deck/domain/entities/audio_source.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/domain/entities/macro_definition.dart';
import 'package:obs_stream_deck/domain/entities/obs_connection_config.dart';
import 'package:obs_stream_deck/domain/entities/obs_runtime_state.dart';
import 'package:obs_stream_deck/domain/entities/recording_status.dart';
import 'package:obs_stream_deck/domain/entities/scene_item.dart';
import 'package:obs_stream_deck/domain/entities/source_item.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';
import 'package:obs_stream_deck/domain/repositories/obs_repository.dart';

import '../fixtures/sample_data.dart';
import 'fake_scene_thumbnail_service.dart';

class FakeObsRepository implements ObsRepository {
  FakeObsRepository({
    ObsRuntimeState? initialState,
    FakeSceneThumbnailService? thumbnailService,
    List<MacroDefinition>? macros,
  })  : _state = initialState ?? sampleObsState(),
        _thumbnailService = thumbnailService ?? FakeSceneThumbnailService() {
    if (macros != null) {
      seedMacros(macros);
    }
  }

  final StreamController<ObsRuntimeState> _stateController =
      StreamController<ObsRuntimeState>.broadcast();
  final FakeSceneThumbnailService _thumbnailService;

  ObsRuntimeState _state;
  ObsConnectionConfig? lastConfig;
  bool appInForeground = true;
  ConnectionStatus? connectFailureStatus;
  String? connectFailureMessage;
  final List<ButtonAction> executedActions = <ButtonAction>[];
  final List<String> actionLog = <String>[];
  final Map<String, MacroDefinition> _macros = <String, MacroDefinition>{};
  final Map<ButtonActionType, Object> actionFailures = <ButtonActionType, Object>{};

  int connectCalls = 0;
  int disconnectCalls = 0;
  int refreshCalls = 0;
  int fetchSceneCalls = 0;
  int fetchAudioCalls = 0;
  int fetchSourceCalls = 0;

  @override
  Stream<ObsRuntimeState> watchState() async* {
    yield _state;
    yield* _stateController.stream;
  }

  @override
  ObsRuntimeState currentState() => _state;

  @override
  Future<void> connect(ObsConnectionConfig config) async {
    connectCalls += 1;
    lastConfig = config;
    _emit(_state.copyWith(connectionStatus: ConnectionStatus.connecting));

    if (connectFailureStatus != null) {
      _emit(
        _state.copyWith(
          connectionStatus: connectFailureStatus,
          lastError: connectFailureMessage,
        ),
      );
      throw Exception(connectFailureMessage ?? 'Connection failed');
    }

    _emit(
      _state.copyWith(
        connectionStatus: ConnectionStatus.connected,
        clearLastError: true,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    _emit(
      _state.copyWith(
        connectionStatus: ConnectionStatus.disconnected,
        streamStatus: StreamStatus.offline,
        recordingStatus: RecordingStatus.stopped,
      ),
    );
  }

  @override
  Future<void> refreshState() async {
    refreshCalls += 1;
    _emit(_state);
  }

  @override
  Future<List<SceneItem>> fetchScenes() async {
    fetchSceneCalls += 1;
    return _state.scenes;
  }

  @override
  Future<List<AudioSource>> fetchAudioSources() async {
    fetchAudioCalls += 1;
    return _state.audioSources;
  }

  @override
  Future<List<SourceItem>> fetchSources() async {
    fetchSourceCalls += 1;
    return _state.sources;
  }

  @override
  Future<String?> fetchSceneThumbnail(
    String sceneName, {
    int width = 192,
    int height = 108,
    int quality = 30,
  }) async {
    return _thumbnailService.thumbnailFor(sceneName);
  }

  @override
  Future<void> executeAction(ButtonAction action) async {
    if (actionFailures.containsKey(action.type)) {
      final failure = actionFailures[action.type]!;
      if (failure is Exception) throw failure;
      throw Exception(failure.toString());
    }

    executedActions.add(action);
    actionLog.add('action:${action.type.name}:${action.targetId ?? action.targetName ?? ''}');

    switch (action.type) {
      case ButtonActionType.switchScene:
        _emit(_state.copyWith(currentScene: _resolveSceneName(action)));
        return;
      case ButtonActionType.setPreviewScene:
        _emit(_state.copyWith(previewScene: _resolveSceneName(action)));
        return;
      case ButtonActionType.mute:
        _setAudioMuted(action, true);
        return;
      case ButtonActionType.unmute:
        _setAudioMuted(action, false);
        return;
      case ButtonActionType.toggleMute:
        _toggleAudio(action);
        return;
      case ButtonActionType.showSource:
        _setSourceVisible(action, true);
        return;
      case ButtonActionType.hideSource:
        _setSourceVisible(action, false);
        return;
      case ButtonActionType.toggleSourceVisibility:
        _toggleSource(action);
        return;
      case ButtonActionType.startStream:
        _emit(_state.copyWith(streamStatus: StreamStatus.live));
        return;
      case ButtonActionType.stopStream:
        _emit(_state.copyWith(streamStatus: StreamStatus.offline));
        return;
      case ButtonActionType.toggleStream:
        _emit(
          _state.copyWith(
            streamStatus: _state.streamStatus == StreamStatus.live
                ? StreamStatus.offline
                : StreamStatus.live,
          ),
        );
        return;
      case ButtonActionType.startRecording:
        _emit(_state.copyWith(recordingStatus: RecordingStatus.recording));
        return;
      case ButtonActionType.stopRecording:
        _emit(_state.copyWith(recordingStatus: RecordingStatus.stopped));
        return;
      case ButtonActionType.pauseRecording:
        _emit(_state.copyWith(recordingStatus: RecordingStatus.paused));
        return;
      case ButtonActionType.resumeRecording:
        _emit(_state.copyWith(recordingStatus: RecordingStatus.recording));
        return;
      case ButtonActionType.toggleRecording:
        _emit(
          _state.copyWith(
            recordingStatus:
                _state.recordingStatus == RecordingStatus.stopped
                    ? RecordingStatus.recording
                    : RecordingStatus.stopped,
          ),
        );
        return;
      case ButtonActionType.startVirtualCamera:
        _emit(_state.copyWith(virtualCameraActive: true));
        return;
      case ButtonActionType.stopVirtualCamera:
        _emit(_state.copyWith(virtualCameraActive: false));
        return;
      case ButtonActionType.toggleVirtualCamera:
        _emit(
          _state.copyWith(virtualCameraActive: !_state.virtualCameraActive),
        );
        return;
      case ButtonActionType.enableStudioMode:
        _emit(_state.copyWith(studioModeEnabled: true));
        return;
      case ButtonActionType.disableStudioMode:
        _emit(_state.copyWith(studioModeEnabled: false));
        return;
      case ButtonActionType.toggleStudioMode:
        _emit(_state.copyWith(studioModeEnabled: !_state.studioModeEnabled));
        return;
      case ButtonActionType.runMacro:
        await runMacro(action.targetId ?? action.targetName ?? '');
        return;
    }
  }

  @override
  Future<void> runMacro(String macroId) async {
    final macro = _macros[macroId];
    if (macro == null) {
      throw Exception('Macro not found: $macroId');
    }

    for (final step in macro.steps) {
      actionLog.add('step:${step.type.name}:${step.targetId ?? step.targetName ?? ''}');
      if (step.type == MacroActionType.delay) {
        await Future<void>.delayed(
          Duration(milliseconds: step.delayMs ?? 0),
        );
        continue;
      }

      await executeAction(
        ButtonAction(
          type: _buttonActionTypeFor(step.type),
          targetId: step.targetId,
          targetName: step.targetName,
        ),
      );
    }
  }

  @override
  void setAppInForeground(bool isForeground) {
    appInForeground = isForeground;
  }

  @override
  void updateConnectionPreferences({
    bool? autoReconnect,
    bool? rememberConnectionInfo,
  }) {}

  void emitState(ObsRuntimeState next) {
    _emit(next);
  }

  void seedMacros(List<MacroDefinition> macros) {
    _macros
      ..clear()
      ..addEntries(macros.map((macro) => MapEntry<String, MacroDefinition>(macro.id, macro)));
  }

  void setScenes(List<SceneItem> scenes, {String? currentScene}) {
    _emit(
      _state.copyWith(
        scenes: scenes,
        currentScene: currentScene ?? (scenes.isEmpty ? null : scenes.first.name),
      ),
    );
  }

  void setCurrentScene(String? sceneName) {
    _emit(_state.copyWith(currentScene: sceneName));
  }

  void setPreviewScene(String? sceneName) {
    _emit(_state.copyWith(previewScene: sceneName));
  }

  void setStreamStatus(StreamStatus status) {
    _emit(_state.copyWith(streamStatus: status));
  }

  void setRecordingStatus(RecordingStatus status) {
    _emit(_state.copyWith(recordingStatus: status));
  }

  void setVirtualCameraActive(bool active) {
    _emit(_state.copyWith(virtualCameraActive: active));
  }

  void setStudioModeEnabled(bool enabled) {
    _emit(_state.copyWith(studioModeEnabled: enabled));
  }

  void setAudioMuted(String id, bool muted) {
    _emit(
      _state.copyWith(
        audioSources: _state.audioSources
            .map((source) => source.id == id ? source.copyWith(isMuted: muted) : source)
            .toList(growable: false),
      ),
    );
  }

  void setSourceVisible(String id, bool visible) {
    _emit(
      _state.copyWith(
        sources: _state.sources
            .map((source) => source.id == id ? source.copyWith(isVisible: visible) : source)
            .toList(growable: false),
      ),
    );
  }

  void setConnectionStatus(ConnectionStatus status, {String? lastError}) {
    _emit(_state.copyWith(connectionStatus: status, lastError: lastError));
  }

  void dispose() {
    _stateController.close();
  }

  void _emit(ObsRuntimeState next) {
    _state = next;
    _stateController.add(next);
  }

  String? _resolveSceneName(ButtonAction action) {
    if (action.targetId != null) {
      final byId = _state.scenes
          .where((scene) => scene.id == action.targetId)
          .map((scene) => scene.name)
          .firstOrNull;
      if (byId != null) return byId;
    }
    if (action.targetName != null) return action.targetName;
    return action.targetId;
  }

  void _setAudioMuted(ButtonAction action, bool muted) {
    final matching = _matchingAudioSources(action);
    final ids = matching.map((item) => item.id).toSet();
    _emit(
      _state.copyWith(
        audioSources: _state.audioSources
            .map((source) => ids.contains(source.id)
                ? source.copyWith(isMuted: muted)
                : source)
            .toList(growable: false),
      ),
    );
  }

  void _toggleAudio(ButtonAction action) {
    final matching = _matchingAudioSources(action);
    final ids = matching.map((item) => item.id).toSet();
    _emit(
      _state.copyWith(
        audioSources: _state.audioSources
            .map((source) => ids.contains(source.id)
                ? source.copyWith(isMuted: !source.isMuted)
                : source)
            .toList(growable: false),
      ),
    );
  }

  void _setSourceVisible(ButtonAction action, bool visible) {
    final matching = _matchingSources(action);
    final ids = matching.map((item) => item.id).toSet();
    _emit(
      _state.copyWith(
        sources: _state.sources
            .map((source) => ids.contains(source.id)
                ? source.copyWith(isVisible: visible)
                : source)
            .toList(growable: false),
      ),
    );
  }

  void _toggleSource(ButtonAction action) {
    final matching = _matchingSources(action);
    final ids = matching.map((item) => item.id).toSet();
    _emit(
      _state.copyWith(
        sources: _state.sources
            .map((source) => ids.contains(source.id)
                ? source.copyWith(isVisible: !source.isVisible)
                : source)
            .toList(growable: false),
      ),
    );
  }

  List<AudioSource> _matchingAudioSources(ButtonAction action) {
    if (action.metadata['all'] == true ||
        _normalize(action.targetId ?? action.targetName ?? '') == 'allaudio') {
      return _state.audioSources;
    }

    return _state.audioSources.where((source) {
      return source.id == action.targetId ||
          source.name == action.targetId ||
          source.id == action.targetName ||
          source.name == action.targetName;
    }).toList(growable: false);
  }

  List<SourceItem> _matchingSources(ButtonAction action) {
    final token = _normalize(action.targetId ?? action.targetName ?? '');
    if (token == 'overlaygroup' || token == 'overlays' || token == 'hideoverlays') {
      return _state.sources.where((source) {
        final normalized = _normalize(source.name);
        return normalized.contains('overlay') ||
            normalized.contains('chat') ||
            normalized.contains('alert') ||
            normalized.contains('browser');
      }).toList(growable: false);
    }

    return _state.sources.where((source) {
      return source.id == action.targetId ||
          source.name == action.targetId ||
          source.id == action.targetName ||
          source.name == action.targetName;
    }).toList(growable: false);
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  ButtonActionType _buttonActionTypeFor(MacroActionType type) {
    switch (type) {
      case MacroActionType.switchScene:
        return ButtonActionType.switchScene;
      case MacroActionType.setPreviewScene:
        return ButtonActionType.setPreviewScene;
      case MacroActionType.showSource:
        return ButtonActionType.showSource;
      case MacroActionType.hideSource:
        return ButtonActionType.hideSource;
      case MacroActionType.toggleSourceVisibility:
        return ButtonActionType.toggleSourceVisibility;
      case MacroActionType.mute:
        return ButtonActionType.mute;
      case MacroActionType.unmute:
        return ButtonActionType.unmute;
      case MacroActionType.toggleMute:
        return ButtonActionType.toggleMute;
      case MacroActionType.startStream:
        return ButtonActionType.startStream;
      case MacroActionType.stopStream:
        return ButtonActionType.stopStream;
      case MacroActionType.startRecording:
        return ButtonActionType.startRecording;
      case MacroActionType.stopRecording:
        return ButtonActionType.stopRecording;
      case MacroActionType.startVirtualCamera:
        return ButtonActionType.startVirtualCamera;
      case MacroActionType.stopVirtualCamera:
        return ButtonActionType.stopVirtualCamera;
      case MacroActionType.enableStudioMode:
        return ButtonActionType.enableStudioMode;
      case MacroActionType.disableStudioMode:
        return ButtonActionType.disableStudioMode;
      case MacroActionType.delay:
      case MacroActionType.runMacro:
        return ButtonActionType.runMacro;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
