import 'dart:async';

import '../../domain/entities/audio_source.dart';
import '../../domain/entities/button_action.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/obs_connection_config.dart';
import '../../domain/entities/obs_runtime_state.dart';
import '../../domain/entities/recording_status.dart';
import '../../domain/entities/scene_item.dart';
import '../../domain/entities/source_item.dart';
import '../../domain/entities/stream_status.dart';
import 'obs_websocket_service.dart';

class MockObsWebSocketService implements ObsWebSocketService {
  MockObsWebSocketService() {
    _state = ObsRuntimeState.initial();
  }

  final _connectionController = StreamController<ConnectionStatus>.broadcast();
  final _streamController = StreamController<StreamStatus>.broadcast();
  final _recordingController = StreamController<RecordingStatus>.broadcast();
  final _sceneController = StreamController<String?>.broadcast();
  final _scenesController = StreamController<List<SceneItem>>.broadcast();
  final _audioController = StreamController<List<AudioSource>>.broadcast();
  final _sourcesController = StreamController<List<SourceItem>>.broadcast();
  final _stateController = StreamController<ObsRuntimeState>.broadcast();

  late ObsRuntimeState _state;

  @override
  Stream<ConnectionStatus> get connectionStatusStream =>
      _connectionController.stream;

  @override
  Stream<StreamStatus> get streamStatusStream => _streamController.stream;

  @override
  Stream<RecordingStatus> get recordingStatusStream =>
      _recordingController.stream;

  @override
  Stream<String?> get currentSceneStream => _sceneController.stream;

  @override
  Stream<List<SceneItem>> get scenesStream => _scenesController.stream;

  @override
  Stream<List<AudioSource>> get audioSourcesStream => _audioController.stream;

  @override
  Stream<List<SourceItem>> get sourcesStream => _sourcesController.stream;

  @override
  Stream<ObsRuntimeState> get stateStream => _stateController.stream;

  @override
  ObsRuntimeState get currentState => _state;

  @override
  Future<void> connect(ObsConnectionConfig config) async {
    _emitState(_state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      clearLastError: true,
    ));

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (config.password.trim().toLowerCase() == 'wrong') {
      _emitState(_state.copyWith(
        connectionStatus: ConnectionStatus.wrongPassword,
        lastError: 'Authentication failed.',
      ));
      return;
    }

    if (config.host.trim() == '0.0.0.0') {
      _emitState(_state.copyWith(
        connectionStatus: ConnectionStatus.notFound,
        lastError: 'Unable to reach OBS host.',
      ));
      return;
    }

    _emitState(
      _state.copyWith(
        connectionStatus: ConnectionStatus.connected,
        scenes: const <SceneItem>[],
        audioSources: const <AudioSource>[],
        sources: _seedSources(),
        currentScene: null,
        previewScene: null,
        studioModeEnabled: true,
        streamStatus: StreamStatus.offline,
        recordingStatus: RecordingStatus.stopped,
        clearLastError: true,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _emitState(
      _state.copyWith(
        connectionStatus: ConnectionStatus.disconnected,
        streamStatus: StreamStatus.offline,
        recordingStatus: RecordingStatus.stopped,
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> sendRequest(
    String requestType, {
    Map<String, dynamic> requestData = const <String, dynamic>{},
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return <String, dynamic>{
      'requestType': requestType,
      'requestData': requestData,
      'responseData': <String, dynamic>{},
    };
  }

  @override
  Future<void> refreshState() async {
    _emitState(_state);
  }

  @override
  Future<List<SceneItem>> fetchScenes() async {
    return _state.scenes;
  }

  @override
  Future<List<AudioSource>> fetchAudioSources() async {
    return _state.audioSources;
  }

  @override
  Future<List<SourceItem>> fetchSources() async {
    return _state.sources;
  }

  @override
  Future<String?> fetchSceneThumbnail(
    String sceneName, {
    int width = 192,
    int height = 108,
    int quality = 30,
  }) async {
    return null;
  }

  @override
  Future<void> executeAction(ButtonAction action) async {
    switch (action.type) {
      case ButtonActionType.switchScene:
        final target = action.targetId ?? action.targetName;
        if (target == null || target.isEmpty) return;
        final resolved = _state.scenes
            .where((scene) => scene.id == target || scene.name == target)
            .map((scene) => scene.name)
            .firstOrNull;
        _emitState(_state.copyWith(currentScene: resolved ?? target));
        break;
      case ButtonActionType.setPreviewScene:
        final target = action.targetId ?? action.targetName;
        if (target == null || target.isEmpty) return;
        if (!_state.studioModeEnabled) return;
        final resolved = _state.scenes
            .where((scene) => scene.id == target || scene.name == target)
            .map((scene) => scene.name)
            .firstOrNull;
        _emitState(_state.copyWith(previewScene: resolved ?? target));
        break;
      case ButtonActionType.showSource:
        _setSourceVisible(action.targetId ?? action.targetName, true);
        break;
      case ButtonActionType.hideSource:
        _setSourceVisible(action.targetId ?? action.targetName, false);
        break;
      case ButtonActionType.toggleSourceVisibility:
        _toggleSource(action.targetId ?? action.targetName);
        break;
      case ButtonActionType.mute:
        _setMute(
          action.targetId ?? action.targetName,
          true,
          _isAllAudioTarget(action),
        );
        break;
      case ButtonActionType.unmute:
        _setMute(
          action.targetId ?? action.targetName,
          false,
          _isAllAudioTarget(action),
        );
        break;
      case ButtonActionType.toggleMute:
        _toggleMute(
          action.targetId ?? action.targetName,
          _isAllAudioTarget(action),
        );
        break;
      case ButtonActionType.startStream:
        _emitState(_state.copyWith(streamStatus: StreamStatus.live));
        break;
      case ButtonActionType.stopStream:
        _emitState(_state.copyWith(streamStatus: StreamStatus.offline));
        break;
      case ButtonActionType.toggleStream:
        final next = _state.streamStatus == StreamStatus.live
            ? StreamStatus.offline
            : StreamStatus.live;
        _emitState(_state.copyWith(streamStatus: next));
        break;
      case ButtonActionType.startRecording:
        _emitState(_state.copyWith(recordingStatus: RecordingStatus.recording));
        break;
      case ButtonActionType.stopRecording:
        _emitState(_state.copyWith(recordingStatus: RecordingStatus.stopped));
        break;
      case ButtonActionType.pauseRecording:
        _emitState(_state.copyWith(recordingStatus: RecordingStatus.paused));
        break;
      case ButtonActionType.resumeRecording:
        _emitState(_state.copyWith(recordingStatus: RecordingStatus.recording));
        break;
      case ButtonActionType.toggleRecording:
        final next = _state.recordingStatus == RecordingStatus.stopped
            ? RecordingStatus.recording
            : RecordingStatus.stopped;
        _emitState(_state.copyWith(recordingStatus: next));
        break;
      case ButtonActionType.runMacro:
        break;
    }
  }

  void _toggleMute(String? targetId, bool all) {
    if (all) {
      final shouldMuteAll =
          !_state.audioSources.every((audio) => audio.isMuted);
      _setMute(targetId, shouldMuteAll, true);
      return;
    }

    final updated = _state.audioSources.map((audio) {
      if (all || audio.id == targetId) {
        return audio.copyWith(isMuted: !audio.isMuted);
      }
      return audio;
    }).toList();

    _emitState(_state.copyWith(audioSources: updated));
  }

  void _setMute(String? targetId, bool muted, bool all) {
    final updated = _state.audioSources.map((audio) {
      if (all || audio.id == targetId) {
        return audio.copyWith(isMuted: muted);
      }
      return audio;
    }).toList();

    _emitState(_state.copyWith(audioSources: updated));
  }

  void _toggleSource(String? sourceId) {
    if (sourceId == null) return;

    final updated = _state.sources.map((source) {
      if (source.id == sourceId ||
          source.name == sourceId ||
          sourceId == 'overlay_group') {
        return source.copyWith(isVisible: !source.isVisible);
      }
      return source;
    }).toList();

    _emitState(_state.copyWith(sources: updated));
  }

  bool _isAllAudioTarget(ButtonAction action) {
    final target = (action.targetId ?? action.targetName ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return action.metadata['all'] == true || target == 'allaudio';
  }

  void _setSourceVisible(String? sourceId, bool visible) {
    if (sourceId == null) return;

    final updated = _state.sources.map((source) {
      if (source.id == sourceId ||
          source.name == sourceId ||
          sourceId == 'overlay_group') {
        return source.copyWith(isVisible: visible);
      }
      return source;
    }).toList();

    _emitState(_state.copyWith(sources: updated));
  }

  void _emitState(ObsRuntimeState state) {
    _state = state;
    _connectionController.add(state.connectionStatus);
    _streamController.add(state.streamStatus);
    _recordingController.add(state.recordingStatus);
    _sceneController.add(state.currentScene);
    _scenesController.add(state.scenes);
    _audioController.add(state.audioSources);
    _sourcesController.add(state.sources);
    _stateController.add(state);
  }

  List<SourceItem> _seedSources() {
    return const <SourceItem>[];
  }

  void dispose() {
    _connectionController.close();
    _streamController.close();
    _recordingController.close();
    _sceneController.close();
    _scenesController.close();
    _audioController.close();
    _sourcesController.close();
    _stateController.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
