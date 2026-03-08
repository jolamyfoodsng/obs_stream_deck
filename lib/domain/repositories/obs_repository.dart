import '../entities/button_action.dart';
import '../entities/audio_source.dart';
import '../entities/obs_connection_config.dart';
import '../entities/obs_runtime_state.dart';
import '../entities/scene_item.dart';
import '../entities/source_item.dart';

abstract class ObsRepository {
  Stream<ObsRuntimeState> watchState();
  ObsRuntimeState currentState();

  Future<void> connect(ObsConnectionConfig config);
  Future<void> disconnect();
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
  Future<void> runMacro(String macroId);
}
