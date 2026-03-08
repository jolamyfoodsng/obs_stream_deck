import '../../domain/entities/button_action.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/obs_connection_config.dart';
import '../../domain/entities/recording_status.dart';
import '../../domain/entities/scene_item.dart';
import '../../domain/entities/source_item.dart';
import '../../domain/entities/stream_status.dart';
import '../../domain/entities/audio_source.dart';
import '../../domain/entities/obs_runtime_state.dart';

abstract class ObsWebSocketService {
  Stream<ConnectionStatus> get connectionStatusStream;
  Stream<StreamStatus> get streamStatusStream;
  Stream<RecordingStatus> get recordingStatusStream;
  Stream<String?> get currentSceneStream;
  Stream<List<SceneItem>> get scenesStream;
  Stream<List<AudioSource>> get audioSourcesStream;
  Stream<List<SourceItem>> get sourcesStream;
  Stream<ObsRuntimeState> get stateStream;

  ObsRuntimeState get currentState;

  Future<void> connect(ObsConnectionConfig config);
  Future<void> disconnect();
  Future<Map<String, dynamic>> sendRequest(
    String requestType, {
    Map<String, dynamic> requestData = const <String, dynamic>{},
  });
  Future<void> refreshState();
  Future<List<SceneItem>> fetchScenes();
  Future<List<AudioSource>> fetchAudioSources();
  Future<List<SourceItem>> fetchSources();
  Future<String?> fetchSceneThumbnail(
    String sceneName, {
    int width = 192,
    int height = 108,
    int quality = 30,
  });
  Future<void> executeAction(ButtonAction action);
}
