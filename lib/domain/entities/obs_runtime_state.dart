import 'audio_source.dart';
import 'connection_status.dart';
import 'recording_status.dart';
import 'scene_item.dart';
import 'source_item.dart';
import 'stream_status.dart';

class ObsRuntimeState {
  const ObsRuntimeState({
    required this.connectionStatus,
    required this.streamStatus,
    required this.recordingStatus,
    required this.currentScene,
    required this.previewScene,
    required this.scenes,
    required this.audioSources,
    required this.sources,
    required this.bitrateKbps,
    required this.droppedFramesPercent,
    required this.cpuUsagePercent,
    required this.uptime,
    required this.studioModeEnabled,
    required this.outputReconnecting,
    required this.outputCongestion,
    required this.outputSkippedFrames,
    required this.outputTotalFrames,
    required this.lastError,
  });

  final ConnectionStatus connectionStatus;
  final StreamStatus streamStatus;
  final RecordingStatus recordingStatus;
  final String? currentScene;
  final String? previewScene;
  final List<SceneItem> scenes;
  final List<AudioSource> audioSources;
  final List<SourceItem> sources;
  final int bitrateKbps;
  final double droppedFramesPercent;
  final double cpuUsagePercent;
  final Duration uptime;
  final bool studioModeEnabled;
  final bool outputReconnecting;
  final double outputCongestion;
  final int outputSkippedFrames;
  final int outputTotalFrames;
  final String? lastError;

  double get outputSkippedFramesPercent {
    if (outputTotalFrames <= 0) return 0;
    return (outputSkippedFrames / outputTotalFrames) * 100;
  }

  factory ObsRuntimeState.initial() {
    return const ObsRuntimeState(
      connectionStatus: ConnectionStatus.disconnected,
      streamStatus: StreamStatus.offline,
      recordingStatus: RecordingStatus.stopped,
      currentScene: null,
      previewScene: null,
      scenes: <SceneItem>[],
      audioSources: <AudioSource>[],
      sources: <SourceItem>[],
      bitrateKbps: 0,
      droppedFramesPercent: 0,
      cpuUsagePercent: 0,
      uptime: Duration.zero,
      studioModeEnabled: false,
      outputReconnecting: false,
      outputCongestion: 0,
      outputSkippedFrames: 0,
      outputTotalFrames: 0,
      lastError: null,
    );
  }

  ObsRuntimeState copyWith({
    ConnectionStatus? connectionStatus,
    StreamStatus? streamStatus,
    RecordingStatus? recordingStatus,
    String? currentScene,
    String? previewScene,
    List<SceneItem>? scenes,
    List<AudioSource>? audioSources,
    List<SourceItem>? sources,
    int? bitrateKbps,
    double? droppedFramesPercent,
    double? cpuUsagePercent,
    Duration? uptime,
    bool? studioModeEnabled,
    bool? outputReconnecting,
    double? outputCongestion,
    int? outputSkippedFrames,
    int? outputTotalFrames,
    String? lastError,
    bool clearLastError = false,
  }) {
    return ObsRuntimeState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      streamStatus: streamStatus ?? this.streamStatus,
      recordingStatus: recordingStatus ?? this.recordingStatus,
      currentScene: currentScene ?? this.currentScene,
      previewScene: previewScene ?? this.previewScene,
      scenes: scenes ?? this.scenes,
      audioSources: audioSources ?? this.audioSources,
      sources: sources ?? this.sources,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      droppedFramesPercent: droppedFramesPercent ?? this.droppedFramesPercent,
      cpuUsagePercent: cpuUsagePercent ?? this.cpuUsagePercent,
      uptime: uptime ?? this.uptime,
      studioModeEnabled: studioModeEnabled ?? this.studioModeEnabled,
      outputReconnecting: outputReconnecting ?? this.outputReconnecting,
      outputCongestion: outputCongestion ?? this.outputCongestion,
      outputSkippedFrames: outputSkippedFrames ?? this.outputSkippedFrames,
      outputTotalFrames: outputTotalFrames ?? this.outputTotalFrames,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
