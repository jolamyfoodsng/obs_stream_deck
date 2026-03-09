import 'dart:async';
import 'dart:collection';

import '../../domain/entities/recording_status.dart';
import '../../domain/entities/stream_status.dart';

typedef ObsStatsRequest = Future<Map<String, dynamic>> Function(
  String requestType,
);

typedef ObsStatsSnapshotListener = void Function(ObsStatsSnapshot snapshot);

class ObsStatsSnapshot {
  const ObsStatsSnapshot({
    required this.streamStatus,
    required this.recordingStatus,
    required this.bitrateKbps,
    required this.droppedFramesPercent,
    required this.cpuUsagePercent,
    required this.activeFps,
    required this.averageFrameRenderTimeMs,
    required this.renderSkippedFrames,
    required this.renderTotalFrames,
    required this.streamDuration,
    required this.streamTimecode,
    required this.streamOutputBytes,
    required this.outputReconnecting,
    required this.outputCongestion,
    required this.outputSkippedFrames,
    required this.outputTotalFrames,
    required this.recordingDuration,
    required this.recordingTimecode,
  });

  final StreamStatus streamStatus;
  final RecordingStatus recordingStatus;
  final int bitrateKbps;
  final double droppedFramesPercent;
  final double cpuUsagePercent;
  final double activeFps;
  final double averageFrameRenderTimeMs;
  final int renderSkippedFrames;
  final int renderTotalFrames;
  final Duration streamDuration;
  final String? streamTimecode;
  final int streamOutputBytes;
  final bool outputReconnecting;
  final double outputCongestion;
  final int outputSkippedFrames;
  final int outputTotalFrames;
  final Duration recordingDuration;
  final String? recordingTimecode;
}

class ObsStatsService {
  ObsStatsService({
    required ObsStatsRequest request,
    required ObsStatsSnapshotListener onSnapshot,
  })  : _request = request,
        _onSnapshot = onSnapshot;

  static const Duration _pollInterval = Duration(seconds: 1);
  static const int _bitrateSmoothingWindow = 5;

  final ObsStatsRequest _request;
  final ObsStatsSnapshotListener _onSnapshot;

  final Queue<double> _recentBitrateSamples = Queue<double>();

  Timer? _pollTimer;
  bool _connected = false;
  bool _appInForeground = true;
  bool _pollInFlight = false;
  int? _lastOutputBytes;
  DateTime? _lastOutputBytesAt;

  void setConnected(bool connected) {
    _connected = connected;
    if (!connected) {
      _resetSampling();
    }
    _configurePolling();
  }

  void setAppInForeground(bool isForeground) {
    if (_appInForeground == isForeground) return;
    _appInForeground = isForeground;
    _configurePolling();
    if (isForeground) {
      unawaited(refreshNow());
    }
  }

  Future<void> refreshNow() async {
    if (!_connected || _pollInFlight) return;

    _pollInFlight = true;
    try {
      final results = await Future.wait<
          Map<String, dynamic>>(<Future<Map<String, dynamic>>>[
        _safeRequest('GetStats'),
        _safeRequest('GetStreamStatus'),
        _safeRequest('GetRecordStatus'),
      ]);

      final snapshot = _buildSnapshot(
        statsData: results[0],
        streamData: results[1],
        recordData: results[2],
      );
      if (snapshot != null) {
        _onSnapshot(snapshot);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _resetSampling();
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;

    if (!_connected || !_appInForeground) {
      return;
    }

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(refreshNow());
    });
  }

  Future<Map<String, dynamic>> _safeRequest(String requestType) async {
    try {
      return await _request(requestType);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  ObsStatsSnapshot? _buildSnapshot({
    required Map<String, dynamic> statsData,
    required Map<String, dynamic> streamData,
    required Map<String, dynamic> recordData,
  }) {
    if (statsData.isEmpty && streamData.isEmpty && recordData.isEmpty) {
      return null;
    }

    final streamActive = streamData['outputActive'] as bool? ?? false;
    final streamStatus = _mapStreamStatus(
      active: streamActive,
      outputState: streamData['outputState'] as String?,
    );

    final recordActive = recordData['outputActive'] as bool? ?? false;
    final recordingStatus = _mapRecordingStatus(
      active: recordActive,
      outputState: recordData['outputState'] as String?,
    );

    final outputSkippedFrames =
        (streamData['outputSkippedFrames'] as num?)?.toInt() ??
            (statsData['outputSkippedFrames'] as num?)?.toInt() ??
            0;
    final outputTotalFrames =
        (streamData['outputTotalFrames'] as num?)?.toInt() ??
            (statsData['outputTotalFrames'] as num?)?.toInt() ??
            0;

    final droppedFramesPercent = outputTotalFrames <= 0
        ? 0.0
        : (outputSkippedFrames / outputTotalFrames) * 100;

    final streamOutputBytes =
        (streamData['outputBytes'] as num?)?.toInt() ?? _lastOutputBytes ?? 0;

    return ObsStatsSnapshot(
      streamStatus: streamStatus,
      recordingStatus: recordingStatus,
      bitrateKbps: _deriveBitrateKbps(
        streamActive: streamActive,
        outputBytes: streamOutputBytes,
      ),
      droppedFramesPercent: streamActive ? droppedFramesPercent : 0.0,
      cpuUsagePercent: (statsData['cpuUsage'] as num?)?.toDouble() ?? 0.0,
      activeFps: (statsData['activeFps'] as num?)?.toDouble() ?? 0.0,
      averageFrameRenderTimeMs:
          (statsData['averageFrameRenderTime'] as num?)?.toDouble() ?? 0.0,
      renderSkippedFrames:
          (statsData['renderSkippedFrames'] as num?)?.toInt() ?? 0,
      renderTotalFrames: (statsData['renderTotalFrames'] as num?)?.toInt() ?? 0,
      streamDuration: streamActive
          ? Duration(
              milliseconds:
                  (streamData['outputDuration'] as num?)?.toInt() ?? 0,
            )
          : Duration.zero,
      streamTimecode:
          streamActive ? streamData['outputTimecode'] as String? : null,
      streamOutputBytes: streamActive ? streamOutputBytes : 0,
      outputReconnecting: streamData['outputReconnecting'] as bool? ?? false,
      outputCongestion:
          (streamData['outputCongestion'] as num?)?.toDouble() ?? 0.0,
      outputSkippedFrames: streamActive ? outputSkippedFrames : 0,
      outputTotalFrames: streamActive ? outputTotalFrames : 0,
      recordingDuration: recordActive
          ? Duration(
              milliseconds:
                  (recordData['outputDuration'] as num?)?.toInt() ?? 0,
            )
          : Duration.zero,
      recordingTimecode:
          recordActive ? recordData['outputTimecode'] as String? : null,
    );
  }

  int _deriveBitrateKbps({
    required bool streamActive,
    required int outputBytes,
  }) {
    if (!streamActive) {
      _resetSampling();
      return 0;
    }

    final now = DateTime.now();
    final previousBytes = _lastOutputBytes;
    final previousAt = _lastOutputBytesAt;

    _lastOutputBytes = outputBytes;
    _lastOutputBytesAt = now;

    if (previousBytes == null ||
        previousAt == null ||
        outputBytes < previousBytes) {
      return _smoothedBitrate();
    }

    final deltaBytes = outputBytes - previousBytes;
    final deltaMs = now.difference(previousAt).inMilliseconds;
    if (deltaMs <= 0) {
      return _smoothedBitrate();
    }

    final kbps = (deltaBytes * 8) / deltaMs;
    if (kbps.isFinite && kbps >= 0) {
      _recentBitrateSamples.add(kbps);
      while (_recentBitrateSamples.length > _bitrateSmoothingWindow) {
        _recentBitrateSamples.removeFirst();
      }
    }

    return _smoothedBitrate();
  }

  int _smoothedBitrate() {
    if (_recentBitrateSamples.isEmpty) return 0;
    final total = _recentBitrateSamples.fold<double>(
      0,
      (sum, sample) => sum + sample,
    );
    return (total / _recentBitrateSamples.length).round();
  }

  void _resetSampling() {
    _recentBitrateSamples.clear();
    _lastOutputBytes = null;
    _lastOutputBytesAt = null;
  }

  StreamStatus _mapStreamStatus({
    required bool active,
    required String? outputState,
  }) {
    final normalized = outputState?.toUpperCase() ?? '';
    if (normalized.contains('STARTING')) return StreamStatus.starting;
    if (normalized.contains('STOPPING')) return StreamStatus.stopping;
    if (normalized.contains('ERROR')) return StreamStatus.error;
    return active ? StreamStatus.live : StreamStatus.offline;
  }

  RecordingStatus _mapRecordingStatus({
    required bool active,
    required String? outputState,
  }) {
    final normalized = outputState?.toUpperCase() ?? '';
    if (normalized.contains('STARTING')) return RecordingStatus.starting;
    if (normalized.contains('STOPPING')) return RecordingStatus.stopping;
    if (normalized.contains('ERROR')) return RecordingStatus.error;
    if (normalized.contains('PAUSE')) return RecordingStatus.paused;
    return active ? RecordingStatus.recording : RecordingStatus.stopped;
  }
}
