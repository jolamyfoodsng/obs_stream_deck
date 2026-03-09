import 'dart:async';

import 'package:obs_stream_deck/core/services/obs_websocket_service.dart';
import 'package:obs_stream_deck/domain/entities/audio_source.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/domain/entities/obs_connection_config.dart';
import 'package:obs_stream_deck/domain/entities/obs_runtime_state.dart';
import 'package:obs_stream_deck/domain/entities/recording_status.dart';
import 'package:obs_stream_deck/domain/entities/scene_item.dart';
import 'package:obs_stream_deck/domain/entities/source_item.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';

import 'fake_obs_repository.dart';

class FakeObsWebSocketService implements ObsWebSocketService {
  FakeObsWebSocketService({FakeObsRepository? repository})
      : repository = repository ?? FakeObsRepository();

  final FakeObsRepository repository;

  @override
  Stream<ConnectionStatus> get connectionStatusStream =>
      repository.watchState().map((state) => state.connectionStatus);

  @override
  ObsRuntimeState get currentState => repository.currentState();

  @override
  Stream<String?> get currentSceneStream =>
      repository.watchState().map((state) => state.currentScene);

  @override
  Stream<RecordingStatus> get recordingStatusStream =>
      repository.watchState().map((state) => state.recordingStatus);

  @override
  Stream<List<AudioSource>> get audioSourcesStream =>
      repository.watchState().map((state) => state.audioSources);

  @override
  Stream<List<SceneItem>> get scenesStream =>
      repository.watchState().map((state) => state.scenes);

  @override
  Stream<List<SourceItem>> get sourcesStream =>
      repository.watchState().map((state) => state.sources);

  @override
  Stream<ObsRuntimeState> get stateStream => repository.watchState();

  @override
  Stream<StreamStatus> get streamStatusStream =>
      repository.watchState().map((state) => state.streamStatus);

  @override
  Future<void> connect(ObsConnectionConfig config) => repository.connect(config);

  @override
  Future<void> disconnect() => repository.disconnect();

  @override
  Future<void> executeAction(ButtonAction action) => repository.executeAction(action);

  @override
  Future<List<AudioSource>> fetchAudioSources() => repository.fetchAudioSources();

  @override
  Future<List<SceneItem>> fetchScenes() => repository.fetchScenes();

  @override
  Future<String?> fetchSceneThumbnail(
    String sceneName, {
    int width = 192,
    int height = 108,
    int quality = 30,
  }) {
    return repository.fetchSceneThumbnail(
      sceneName,
      width: width,
      height: height,
      quality: quality,
    );
  }

  @override
  Future<List<SourceItem>> fetchSources() => repository.fetchSources();

  @override
  Future<void> refreshState() => repository.refreshState();

  @override
  Future<Map<String, dynamic>> sendRequest(
    String requestType, {
    Map<String, dynamic> requestData = const <String, dynamic>{},
  }) async {
    return <String, dynamic>{
      'requestType': requestType,
      'requestData': requestData,
      'ok': true,
    };
  }

  @override
  void setAppInForeground(bool isForeground) {
    repository.setAppInForeground(isForeground);
  }

  @override
  void updateConnectionPreferences({
    bool? autoReconnect,
    bool? rememberConnectionInfo,
  }) {
    repository.updateConnectionPreferences(
      autoReconnect: autoReconnect,
      rememberConnectionInfo: rememberConnectionInfo,
    );
  }
}
