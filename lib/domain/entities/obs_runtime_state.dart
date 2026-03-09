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
    required this.audioMetersAvailable,
    required this.microphoneSilent,
    required this.silentMicrophoneName,
    required this.bitrateKbps,
    required this.droppedFramesPercent,
    required this.cpuUsagePercent,
    required this.activeFps,
    required this.averageFrameRenderTimeMs,
    required this.renderSkippedFrames,
    required this.renderTotalFrames,
    required this.uptime,
    required this.streamTimecode,
    required this.streamOutputBytes,
    required this.studioModeEnabled,
    required this.virtualCameraActive,
    required this.connectionLatencyMs,
    required this.outputReconnecting,
    required this.outputCongestion,
    required this.outputSkippedFrames,
    required this.outputTotalFrames,
    required this.recordingDuration,
    required this.recordingTimecode,
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
  final bool audioMetersAvailable;
  final bool microphoneSilent;
  final String? silentMicrophoneName;
  final int bitrateKbps;
  final double droppedFramesPercent;
  final double cpuUsagePercent;
  final double activeFps;
  final double averageFrameRenderTimeMs;
  final int renderSkippedFrames;
  final int renderTotalFrames;
  final Duration uptime;
  final String? streamTimecode;
  final int streamOutputBytes;
  final bool studioModeEnabled;
  final bool virtualCameraActive;
  final int? connectionLatencyMs;
  final bool outputReconnecting;
  final double outputCongestion;
  final int outputSkippedFrames;
  final int outputTotalFrames;
  final Duration recordingDuration;
  final String? recordingTimecode;
  final String? lastError;

  double get outputSkippedFramesPercent {
    if (outputTotalFrames <= 0) return 0;
    return (outputSkippedFrames / outputTotalFrames) * 100;
  }

  double get renderSkippedFramesPercent {
    if (renderTotalFrames <= 0) return 0;
    return (renderSkippedFrames / renderTotalFrames) * 100;
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
      audioMetersAvailable: false,
      microphoneSilent: false,
      silentMicrophoneName: null,
      bitrateKbps: 0,
      droppedFramesPercent: 0,
      cpuUsagePercent: 0,
      activeFps: 0,
      averageFrameRenderTimeMs: 0,
      renderSkippedFrames: 0,
      renderTotalFrames: 0,
      uptime: Duration.zero,
      streamTimecode: null,
      streamOutputBytes: 0,
      studioModeEnabled: false,
      virtualCameraActive: false,
      connectionLatencyMs: null,
      outputReconnecting: false,
      outputCongestion: 0,
      outputSkippedFrames: 0,
      outputTotalFrames: 0,
      recordingDuration: Duration.zero,
      recordingTimecode: null,
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
    bool? audioMetersAvailable,
    bool? microphoneSilent,
    Object? silentMicrophoneName = _sentinel,
    int? bitrateKbps,
    double? droppedFramesPercent,
    double? cpuUsagePercent,
    double? activeFps,
    double? averageFrameRenderTimeMs,
    int? renderSkippedFrames,
    int? renderTotalFrames,
    Duration? uptime,
    Object? streamTimecode = _sentinel,
    int? streamOutputBytes,
    bool? studioModeEnabled,
    bool? virtualCameraActive,
    Object? connectionLatencyMs = _sentinel,
    bool? outputReconnecting,
    double? outputCongestion,
    int? outputSkippedFrames,
    int? outputTotalFrames,
    Duration? recordingDuration,
    Object? recordingTimecode = _sentinel,
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
      audioMetersAvailable: audioMetersAvailable ?? this.audioMetersAvailable,
      microphoneSilent: microphoneSilent ?? this.microphoneSilent,
      silentMicrophoneName: identical(silentMicrophoneName, _sentinel)
          ? this.silentMicrophoneName
          : silentMicrophoneName as String?,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      droppedFramesPercent: droppedFramesPercent ?? this.droppedFramesPercent,
      cpuUsagePercent: cpuUsagePercent ?? this.cpuUsagePercent,
      activeFps: activeFps ?? this.activeFps,
      averageFrameRenderTimeMs:
          averageFrameRenderTimeMs ?? this.averageFrameRenderTimeMs,
      renderSkippedFrames: renderSkippedFrames ?? this.renderSkippedFrames,
      renderTotalFrames: renderTotalFrames ?? this.renderTotalFrames,
      uptime: uptime ?? this.uptime,
      streamTimecode: identical(streamTimecode, _sentinel)
          ? this.streamTimecode
          : streamTimecode as String?,
      streamOutputBytes: streamOutputBytes ?? this.streamOutputBytes,
      studioModeEnabled: studioModeEnabled ?? this.studioModeEnabled,
      virtualCameraActive: virtualCameraActive ?? this.virtualCameraActive,
      connectionLatencyMs: identical(connectionLatencyMs, _sentinel)
          ? this.connectionLatencyMs
          : connectionLatencyMs as int?,
      outputReconnecting: outputReconnecting ?? this.outputReconnecting,
      outputCongestion: outputCongestion ?? this.outputCongestion,
      outputSkippedFrames: outputSkippedFrames ?? this.outputSkippedFrames,
      outputTotalFrames: outputTotalFrames ?? this.outputTotalFrames,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      recordingTimecode: identical(recordingTimecode, _sentinel)
          ? this.recordingTimecode
          : recordingTimecode as String?,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  static const Object _sentinel = Object();
}
