class DashboardStats {
  const DashboardStats({
    required this.bitrateKbps,
    required this.droppedFramesPercent,
    required this.cpuUsagePercent,
    required this.uptime,
    required this.audioLevels,
    required this.connectionHealth,
  });

  final int bitrateKbps;
  final double droppedFramesPercent;
  final double cpuUsagePercent;
  final Duration uptime;
  final Map<String, double> audioLevels;
  final String connectionHealth;

  DashboardStats copyWith({
    int? bitrateKbps,
    double? droppedFramesPercent,
    double? cpuUsagePercent,
    Duration? uptime,
    Map<String, double>? audioLevels,
    String? connectionHealth,
  }) {
    return DashboardStats(
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      droppedFramesPercent: droppedFramesPercent ?? this.droppedFramesPercent,
      cpuUsagePercent: cpuUsagePercent ?? this.cpuUsagePercent,
      uptime: uptime ?? this.uptime,
      audioLevels: audioLevels ?? this.audioLevels,
      connectionHealth: connectionHealth ?? this.connectionHealth,
    );
  }
}
