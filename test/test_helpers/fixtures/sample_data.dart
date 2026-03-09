import 'package:obs_stream_deck/domain/entities/audio_source.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/domain/entities/controller_button.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';
import 'package:obs_stream_deck/domain/entities/macro_definition.dart';
import 'package:obs_stream_deck/domain/entities/obs_connection_config.dart';
import 'package:obs_stream_deck/domain/entities/obs_runtime_state.dart';
import 'package:obs_stream_deck/domain/entities/saved_obs_connection.dart';
import 'package:obs_stream_deck/domain/entities/scene_item.dart';
import 'package:obs_stream_deck/domain/entities/source_item.dart';
import 'package:obs_stream_deck/domain/entities/recording_status.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';

List<SceneItem> sampleScenes({int count = 8, int activeIndex = 0}) {
  return List<SceneItem>.generate(
    count,
    (index) => SceneItem(
      id: 'scene_$index',
      name: 'Scene ${index + 1}',
      isProgram: index == activeIndex,
    ),
    growable: false,
  );
}

List<AudioSource> sampleAudioSources() {
  return const <AudioSource>[
    AudioSource(
      id: 'mic_main',
      name: 'Main Mic',
      isMuted: false,
      volume: 0.85,
      levelDb: -12,
      hasLiveMeter: true,
    ),
    AudioSource(
      id: 'desktop_main',
      name: 'Desktop Audio',
      isMuted: false,
      volume: 0.78,
      levelDb: -18,
      hasLiveMeter: true,
    ),
  ];
}

List<SourceItem> sampleSources() {
  return const <SourceItem>[
    SourceItem(
      id: 'camera_main',
      name: 'Camera',
      sceneId: 'scene_0',
      isVisible: true,
    ),
    SourceItem(
      id: 'overlay_chat',
      name: 'Chat Overlay',
      sceneId: 'scene_0',
      isVisible: true,
    ),
  ];
}

ObsRuntimeState sampleObsState({
  ConnectionStatus connectionStatus = ConnectionStatus.connected,
  StreamStatus streamStatus = StreamStatus.offline,
  RecordingStatus recordingStatus = RecordingStatus.stopped,
  String? currentScene,
  String? previewScene,
  List<SceneItem>? scenes,
  List<AudioSource>? audioSources,
  List<SourceItem>? sources,
  bool studioModeEnabled = false,
  bool virtualCameraActive = false,
  int? connectionLatencyMs = 8,
  bool outputReconnecting = false,
  double outputCongestion = 0,
  int outputSkippedFrames = 0,
  int outputTotalFrames = 0,
  int bitrateKbps = 4500,
  double droppedFramesPercent = 0,
  double cpuUsagePercent = 14,
  double activeFps = 60,
  double averageFrameRenderTimeMs = 2.4,
  int renderSkippedFrames = 0,
  int renderTotalFrames = 1,
  Duration uptime = const Duration(minutes: 5),
  Duration recordingDuration = const Duration(minutes: 2),
  int streamOutputBytes = 1024 * 1024,
  bool microphoneSilent = false,
  String? silentMicrophoneName,
  String? lastError,
}) {
  final resolvedScenes = scenes ?? sampleScenes();
  final resolvedCurrentScene =
      currentScene ?? (resolvedScenes.isEmpty ? null : resolvedScenes.first.name);
  return ObsRuntimeState(
    connectionStatus: connectionStatus,
    streamStatus: streamStatus,
    recordingStatus: recordingStatus,
    currentScene: resolvedCurrentScene,
    previewScene: previewScene,
    scenes: resolvedScenes,
    audioSources: audioSources ?? sampleAudioSources(),
    sources: sources ?? sampleSources(),
    audioMetersAvailable: true,
    microphoneSilent: microphoneSilent,
    silentMicrophoneName: silentMicrophoneName,
    bitrateKbps: bitrateKbps,
    droppedFramesPercent: droppedFramesPercent,
    cpuUsagePercent: cpuUsagePercent,
    activeFps: activeFps,
    averageFrameRenderTimeMs: averageFrameRenderTimeMs,
    renderSkippedFrames: renderSkippedFrames,
    renderTotalFrames: renderTotalFrames,
    uptime: uptime,
    streamTimecode: '00:05:00.000',
    streamOutputBytes: streamOutputBytes,
    studioModeEnabled: studioModeEnabled,
    virtualCameraActive: virtualCameraActive,
    connectionLatencyMs: connectionLatencyMs,
    outputReconnecting: outputReconnecting,
    outputCongestion: outputCongestion,
    outputSkippedFrames: outputSkippedFrames,
    outputTotalFrames: outputTotalFrames,
    recordingDuration: recordingDuration,
    recordingTimecode: '00:02:00.000',
    lastError: lastError,
  );
}

ControllerPage sampleScenesPage({
  String id = 'scenes',
  String name = 'Scenes',
  List<ControllerButton>? buttons,
}) {
  return ControllerPage(
    id: id,
    name: name,
    columns: 3,
    rows: 4,
    buttons: buttons ?? const <ControllerButton>[],
    isDefault: true,
  );
}

ControllerPage sampleCustomPage({
  String id = 'media',
  String name = 'Media',
  List<ControllerButton>? buttons,
}) {
  return ControllerPage(
    id: id,
    name: name,
    columns: 3,
    rows: 4,
    buttons: buttons ?? const <ControllerButton>[],
    isDefault: false,
  );
}

ControllerButton sampleSceneButton({
  String id = 'btn_scene_0',
  String label = 'Scene 1',
  String targetId = 'scene_0',
  int position = 0,
}) {
  return ControllerButton(
    id: id,
    label: label,
    icon: 'movie',
    activeColor: '#137FEC',
    inactiveColor: '#64748B',
    category: DeckButtonCategory.scene,
    action: ButtonAction(
      type: ButtonActionType.switchScene,
      targetId: targetId,
      targetName: label,
    ),
    position: position,
  );
}

ControllerButton sampleMuteMicButton({bool longPressTrigger = false}) {
  return ControllerButton(
    id: 'btn_mic',
    label: 'Mute Mic',
    icon: 'mic_off',
    activeColor: '#F59E0B',
    inactiveColor: '#64748B',
    category: DeckButtonCategory.audio,
    action: const ButtonAction(
      type: ButtonActionType.toggleMute,
      targetId: 'mic_main',
      targetName: 'Main Mic',
    ),
    position: 0,
    longPressTrigger: longPressTrigger,
  );
}

MacroDefinition sampleMacro({
  String id = 'macro_start_service',
  String name = 'Start Service',
  List<MacroAction>? steps,
}) {
  return MacroDefinition(
    id: id,
    name: name,
    icon: 'bolt',
    colorHex: '#8B5CF6',
    steps: steps ??
        const <MacroAction>[
          MacroAction(
            id: 'step_1',
            type: MacroActionType.switchScene,
            targetId: 'scene_0',
            targetName: 'Scene 1',
          ),
          MacroAction(
            id: 'step_2',
            type: MacroActionType.delay,
            delayMs: 20,
          ),
          MacroAction(
            id: 'step_3',
            type: MacroActionType.startStream,
          ),
        ],
  );
}

ObsConnectionConfig sampleConnectionConfig({
  String host = '192.168.1.8',
  int port = 4455,
  String password = 'secret',
}) {
  return ObsConnectionConfig(host: host, port: port, password: password);
}

SavedObsConnection sampleSavedConnection({
  String id = 'saved_1',
  String label = 'Studio Mac',
  String host = '192.168.1.8',
  int port = 4455,
  String password = 'secret',
}) {
  return SavedObsConnection(
    id: id,
    label: label,
    host: host,
    port: port,
    password: password,
    lastConnectedAt: DateTime(2026, 3, 1),
  );
}
