import 'dart:async';

import 'package:obs_stream_deck/domain/entities/dashboard_stats.dart';
import 'package:obs_stream_deck/domain/repositories/dashboard_repository.dart';

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({DashboardStats? initialStats})
      : _stats = initialStats ??
            const DashboardStats(
              bitrateKbps: 4500,
              droppedFramesPercent: 0.0,
              cpuUsagePercent: 14.0,
              uptime: Duration(minutes: 5),
              audioLevels: <String, double>{'Main Mic': -12},
              connectionHealth: 'stable',
            );

  final StreamController<DashboardStats> _controller =
      StreamController<DashboardStats>.broadcast();
  DashboardStats _stats;

  @override
  Stream<DashboardStats> watchStats() async* {
    yield _stats;
    yield* _controller.stream;
  }

  void emit(DashboardStats stats) {
    _stats = stats;
    _controller.add(stats);
  }

  void dispose() {
    _controller.close();
  }
}
