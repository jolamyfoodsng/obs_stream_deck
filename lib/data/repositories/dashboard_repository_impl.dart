import 'dart:async';

import '../../domain/entities/dashboard_stats.dart';
import '../../domain/entities/obs_runtime_state.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/repositories/obs_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl(this._obsRepository);

  final ObsRepository _obsRepository;

  @override
  Stream<DashboardStats> watchStats() {
    return _obsRepository.watchState().map((state) {
      return _fromObsState(state);
    }).startWith(_fromObsState(_obsRepository.currentState()));
  }

  DashboardStats _fromObsState(ObsRuntimeState state) {
    final audioLevels = <String, double>{
      for (final source in state.audioSources)
        source.name: source.isMuted ? -60.0 : source.levelDb,
    };

    return DashboardStats(
      bitrateKbps: state.bitrateKbps,
      droppedFramesPercent: state.droppedFramesPercent,
      cpuUsagePercent: state.cpuUsagePercent,
      uptime: state.uptime,
      audioLevels: audioLevels,
      connectionHealth: state.connectionStatus.name,
    );
  }
}

extension _StartWithExtension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
