import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/dashboard_stats.dart';
import '../../../../domain/entities/obs_runtime_state.dart';
import '../../../../domain/repositories/dashboard_repository.dart';
import '../../../../domain/repositories/obs_repository.dart';
import '../../../../shared/state/app_providers.dart';

class DashboardState {
  const DashboardState({
    required this.stats,
    required this.obsState,
  });

  final DashboardStats stats;
  final ObsRuntimeState obsState;

  DashboardState copyWith({
    DashboardStats? stats,
    ObsRuntimeState? obsState,
  }) {
    return DashboardState(
      stats: stats ?? this.stats,
      obsState: obsState ?? this.obsState,
    );
  }

  factory DashboardState.initial(ObsRuntimeState obsState) {
    return DashboardState(
      stats: DashboardStats(
        bitrateKbps: obsState.bitrateKbps,
        droppedFramesPercent: obsState.droppedFramesPercent,
        cpuUsagePercent: obsState.cpuUsagePercent,
        uptime: obsState.uptime,
        audioLevels: const <String, double>{},
        connectionHealth: obsState.connectionStatus.name,
      ),
      obsState: obsState,
    );
  }
}

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController({
    required DashboardRepository dashboardRepository,
    required ObsRepository obsRepository,
  })  : _dashboardRepository = dashboardRepository,
        _obsRepository = obsRepository,
        super(DashboardState.initial(obsRepository.currentState())) {
    _init();
  }

  final DashboardRepository _dashboardRepository;
  final ObsRepository _obsRepository;

  StreamSubscription? _statsSub;
  StreamSubscription? _obsSub;

  void _init() {
    _statsSub = _dashboardRepository.watchStats().listen((stats) {
      state = state.copyWith(stats: stats);
    });

    _obsSub = _obsRepository.watchState().listen((obsState) {
      state = state.copyWith(obsState: obsState);
    });
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _obsSub?.cancel();
    super.dispose();
  }
}

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
  return DashboardController(
    dashboardRepository: ref.watch(dashboardRepositoryProvider),
    obsRepository: ref.watch(obsRepositoryProvider),
  );
});
