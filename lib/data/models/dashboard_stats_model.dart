import '../../domain/entities/dashboard_stats.dart';

class DashboardStatsModel {
  const DashboardStatsModel._();

  static Map<String, dynamic> toJson(DashboardStats stats) {
    return <String, dynamic>{
      'bitrateKbps': stats.bitrateKbps,
      'droppedFramesPercent': stats.droppedFramesPercent,
      'cpuUsagePercent': stats.cpuUsagePercent,
      'uptimeSeconds': stats.uptime.inSeconds,
      'audioLevels': stats.audioLevels,
      'connectionHealth': stats.connectionHealth,
    };
  }

  static DashboardStats fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt() ?? 0,
      droppedFramesPercent:
          (json['droppedFramesPercent'] as num?)?.toDouble() ?? 0,
      cpuUsagePercent: (json['cpuUsagePercent'] as num?)?.toDouble() ?? 0,
      uptime: Duration(seconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0),
      audioLevels: (json['audioLevels'] as Map?)?.map(
            (key, value) => MapEntry(key as String, (value as num).toDouble()),
          ) ??
          <String, double>{},
      connectionHealth: json['connectionHealth'] as String? ?? 'Unknown',
    );
  }
}
