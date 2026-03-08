import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/stream_status.dart';
import '../../../../shared/extensions/duration_extensions.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../../../../shared/widgets/dashboard_metric_card.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../controllers/dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    final stats = state.stats;
    final obsState = state.obsState;

    final connected = obsState.connectionStatus == ConnectionStatus.connected;
    final streamLive = obsState.streamStatus == StreamStatus.live;
    final bitrateLow =
        streamLive && stats.bitrateKbps > 0 && stats.bitrateKbps < 1200;
    final framesDropping = streamLive &&
        (stats.droppedFramesPercent >= 1.0 ||
            obsState.outputSkippedFramesPercent >= 1.0);
    final networkUnstable = streamLive &&
        (obsState.outputReconnecting || obsState.outputCongestion >= 0.15);

    final streamLabel = switch (obsState.streamStatus) {
      StreamStatus.live => 'Live',
      StreamStatus.starting => 'Starting',
      StreamStatus.stopping => 'Stopping',
      StreamStatus.offline => 'Offline',
      StreamStatus.error => 'Error',
    };

    final networkLabel = !connected
        ? 'Disconnected'
        : networkUnstable
            ? 'Unstable'
            : 'Stable';

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const BrandAppBarTitle(title: 'Monitor'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StatusBadge(
              label: streamLive ? 'Live' : 'Offline',
              color: streamLive
                  ? AppColors.dangerRed
                  : Theme.of(context).colorScheme.outline,
              icon: streamLive ? Icons.fiber_manual_record : Icons.pause_circle,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _ObsConnectionIndicator(
              connected: connected,
              statusLabel: connected ? 'OBS Connected' : 'OBS Disconnected',
            ),
            if (bitrateLow || framesDropping || networkUnstable) ...<Widget>[
              const SizedBox(height: 10),
              if (bitrateLow)
                const _MonitorWarningBanner(
                  icon: Icons.speed,
                  message:
                      'Bitrate is low. Check encoder settings and network throughput.',
                ),
              if (framesDropping)
                const _MonitorWarningBanner(
                  icon: Icons.warning_amber_rounded,
                  message:
                      'Dropped frames detected. Stream output quality may degrade.',
                ),
              if (networkUnstable)
                const _MonitorWarningBanner(
                  icon: Icons.wifi_tethering_error_rounded,
                  message:
                      'Network instability detected. OBS reports congestion/reconnect activity.',
                ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Stream Status',
                    value: streamLabel,
                    caption: connected ? 'OBS online' : 'OBS offline',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Connection',
                    value: connected ? 'Connected' : 'Disconnected',
                    caption: stats.connectionHealth.toUpperCase(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Bitrate',
                    value: '${stats.bitrateKbps} kbps',
                    caption: 'Current output bitrate',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Dropped Frames',
                    value: '${stats.droppedFramesPercent.toStringAsFixed(1)}%',
                    caption:
                        '${obsState.outputSkippedFrames} skipped / ${obsState.outputTotalFrames} total',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DashboardMetricCard(
                    title: 'CPU Usage',
                    value: '${stats.cpuUsagePercent.toStringAsFixed(0)}%',
                    caption: 'Encoder/system load',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Network Stability',
                    value: networkLabel,
                    caption: obsState.outputReconnecting
                        ? 'Reconnect in progress'
                        : 'Congestion ${(obsState.outputCongestion * 100).toStringAsFixed(0)}%',
                    color: networkUnstable
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DashboardMetricCard(
              title: 'Stream Uptime',
              value: stats.uptime.toHms(),
              caption: 'Live session timer',
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.monitor,
      ),
    );
  }
}

class _ObsConnectionIndicator extends StatelessWidget {
  const _ObsConnectionIndicator({
    required this.connected,
    required this.statusLabel,
  });

  final bool connected;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final tone = connected
        ? const Color(0xFF22C55E)
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _MonitorWarningBanner extends StatelessWidget {
  const _MonitorWarningBanner({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
