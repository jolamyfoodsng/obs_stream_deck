import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/audio_source.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/premium_feature.dart';
import '../../../../domain/entities/recording_status.dart';
import '../../../../domain/entities/stream_status.dart';
import '../../../../shared/extensions/duration_extensions.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../../../../shared/widgets/dashboard_metric_card.dart';
import '../../../../shared/widgets/page_helper_text.dart';
import '../../../../shared/widgets/premium_upgrade_modal.dart';
import '../../../../shared/widgets/pro_badge.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../controllers/dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumControllerProvider);
    final state = ref.watch(dashboardControllerProvider);
    final stats = state.stats;
    final obsState = state.obsState;
    final audioSources = <AudioSource>[...obsState.audioSources]
      ..sort(_compareAudioSources);

    final connected = obsState.connectionStatus == ConnectionStatus.connected;
    final streamLive = obsState.streamStatus == StreamStatus.live;
    final recordingActive =
        obsState.recordingStatus == RecordingStatus.recording ||
            obsState.recordingStatus == RecordingStatus.paused;
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
    final recordingLabel = switch (obsState.recordingStatus) {
      RecordingStatus.recording => 'Recording',
      RecordingStatus.paused => 'Paused',
      RecordingStatus.starting => 'Starting',
      RecordingStatus.stopping => 'Stopping',
      RecordingStatus.error => 'Error',
      RecordingStatus.stopped => 'Stopped',
    };

    final networkLabel = !connected
        ? 'Disconnected'
        : networkUnstable
            ? 'Unstable'
            : 'Stable';
    final virtualCamLabel = obsState.virtualCameraActive ? 'On' : 'Off';
    final studioModeLabel = obsState.studioModeEnabled ? 'On' : 'Off';
    final bitrateValue = streamLive ? '${stats.bitrateKbps} kbps' : 'Offline';
    final cpuValue =
        connected ? '${obsState.cpuUsagePercent.toStringAsFixed(1)}%' : '--';
    final fpsValue = connected ? obsState.activeFps.toStringAsFixed(2) : '--';
    final renderTimeValue = connected
        ? '${obsState.averageFrameRenderTimeMs.toStringAsFixed(2)} ms'
        : '--';
    final streamTimerValue = streamLive
        ? (obsState.streamTimecode ?? stats.uptime.toHms())
        : 'Offline';
    final recordTimerValue = recordingActive
        ? (obsState.recordingTimecode ?? obsState.recordingDuration.toHms())
        : 'Stopped';

    Future<void> openMonitorUpgrade() async {
      await showPremiumUpgradeModal(
        context,
        highlightedFeature: PremiumFeature.streamHealthMonitoring,
      );
    }

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
            const PageHelperText(
              text: 'Monitor stream health in real time.',
              padding: EdgeInsets.fromLTRB(0, 0, 0, 10),
            ),
            _ObsConnectionIndicator(
              connected: connected,
              statusLabel: connected ? 'OBS Connected' : 'OBS Disconnected',
            ),
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
                    title: 'Recording',
                    value: recordingLabel,
                    caption: recordingActive
                        ? 'OBS recording output active'
                        : 'OBS recording output inactive',
                    color: recordingActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Stream Timer',
                    value: streamTimerValue,
                    caption: streamLive
                        ? 'From OBS GetStreamStatus'
                        : 'Stream output offline',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Record Timer',
                    value: recordTimerValue,
                    caption: recordingActive
                        ? 'From OBS GetRecordStatus'
                        : 'Recording output offline',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Virtual Camera',
                    value: virtualCamLabel,
                    caption: obsState.virtualCameraActive
                        ? 'Virtual camera active'
                        : 'Virtual camera inactive',
                    color: obsState.virtualCameraActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DashboardMetricCard(
                    title: 'Studio Mode',
                    value: studioModeLabel,
                    caption: obsState.studioModeEnabled
                        ? 'Preview controls available'
                        : 'Preview controls disabled',
                    color: obsState.studioModeEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MonitorSectionHeader(
              premiumLocked: !premium.isPremium,
              title: 'Advanced Stream Health',
              subtitle:
                  'Bitrate, dropped frames, congestion, and warning banners.',
            ),
            const SizedBox(height: 10),
            if (premium.isPremium) ...<Widget>[
              if (bitrateLow || framesDropping || networkUnstable) ...<Widget>[
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
                const SizedBox(height: 2),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: DashboardMetricCard(
                      title: 'Bitrate',
                      value: bitrateValue,
                      caption: streamLive
                          ? 'Derived from OBS outputBytes delta'
                          : 'Stream output offline',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DashboardMetricCard(
                      title: 'Dropped Frames',
                      value:
                          '${stats.droppedFramesPercent.toStringAsFixed(1)}%',
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
                      value: cpuValue,
                      caption: connected
                          ? 'From OBS GetStats.cpuUsage'
                          : 'Connect OBS to fetch render stats',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DashboardMetricCard(
                      title: 'FPS',
                      value: fpsValue,
                      caption: connected
                          ? 'From OBS GetStats.activeFps'
                          : 'Connect OBS to fetch render stats',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DashboardMetricCard(
                      title: 'Render Time',
                      value: renderTimeValue,
                      caption: connected
                          ? 'Avg render time from OBS GetStats'
                          : 'Connect OBS to fetch render stats',
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
            ] else ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _LockedMetricCard(
                      title: 'Bitrate',
                      caption: 'Live output bitrate',
                      onTap: openMonitorUpgrade,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LockedMetricCard(
                      title: 'Dropped Frames',
                      caption: 'Skipped/dropped frame tracking',
                      onTap: openMonitorUpgrade,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _LockedMetricCard(
                      title: 'CPU Usage',
                      caption: 'Encoder and system load',
                      onTap: openMonitorUpgrade,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LockedMetricCard(
                      title: 'FPS',
                      caption: 'Real OBS render frame rate',
                      onTap: openMonitorUpgrade,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _LockedMetricCard(
                      title: 'Render Time',
                      caption: 'Average OBS frame render time',
                      onTap: openMonitorUpgrade,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LockedMetricCard(
                      title: 'Network Stability',
                      caption: 'Congestion and reconnect warnings',
                      onTap: openMonitorUpgrade,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _MonitorSectionHeader(
              premiumLocked: false,
              title: 'Audio Monitoring',
              subtitle: premium.isPremium
                  ? 'Live OBS meters, decibel readouts, and mute state for every audio input.'
                  : 'Free includes mute state and a basic meter. Premium unlocks live dB values and silence warnings.',
            ),
            const SizedBox(height: 10),
            if (premium.isPremium && obsState.microphoneSilent)
              const _MonitorWarningBanner(
                icon: Icons.mic_off_rounded,
                message: 'Microphone appears silent',
              ),
            if (audioSources.isEmpty)
              _EmptyMonitorCard(
                message: connected
                    ? 'No OBS audio inputs are available yet.'
                    : 'Connect OBS to monitor Mic/Aux, Desktop Audio, and other live inputs.',
              )
            else
              ...audioSources.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AudioMeterCard(
                    source: source,
                    metersAvailable: obsState.audioMetersAvailable,
                    showDetailedValues: premium.isPremium,
                  ),
                ),
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

int _compareAudioSources(AudioSource left, AudioSource right) {
  final priorityCompare =
      _audioPriority(left.name).compareTo(_audioPriority(right.name));
  if (priorityCompare != 0) return priorityCompare;
  return left.name.toLowerCase().compareTo(right.name.toLowerCase());
}

int _audioPriority(String name) {
  if (_looksLikeMicrophone(name)) return 0;
  if (_looksLikeDesktopAudio(name)) return 1;
  return 2;
}

bool _looksLikeMicrophone(String name) {
  final normalized = _normalizeAudioName(name);
  const keywords = <String>[
    'mic',
    'microphone',
    'aux',
    'voice',
    'xlr',
    'headset',
    'lav',
    'boom',
    'wireless',
  ];
  return keywords.any(normalized.contains);
}

bool _looksLikeDesktopAudio(String name) {
  final normalized = _normalizeAudioName(name);
  const keywords = <String>[
    'desktop',
    'system',
    'speaker',
    'output',
    'game',
    'music',
    'media',
    'monitor',
  ];
  return keywords.any(normalized.contains);
}

String _normalizeAudioName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _MonitorSectionHeader extends StatelessWidget {
  const _MonitorSectionHeader({
    required this.premiumLocked,
    required this.title,
    required this.subtitle,
  });

  final bool premiumLocked;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (premiumLocked) ...<Widget>[
              const SizedBox(width: 8),
              const ProBadge(compact: true),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _LockedMetricCard extends StatelessWidget {
  const _LockedMetricCard({
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.78,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(letterSpacing: 0.8),
                      ),
                    ),
                    const ProBadge(compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Locked',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Unlock live OBS telemetry',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMonitorCard extends StatelessWidget {
  const _EmptyMonitorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _AudioMeterCard extends StatelessWidget {
  const _AudioMeterCard({
    required this.source,
    required this.metersAvailable,
    required this.showDetailedValues,
  });

  final AudioSource source;
  final bool metersAvailable;
  final bool showDetailedValues;

  @override
  Widget build(BuildContext context) {
    final hasLiveMeter = metersAvailable && source.hasLiveMeter;
    final meterColor = _meterColor(context);
    final statusLabel = _statusLabel(hasLiveMeter);
    final statusTone = source.isMuted
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    source.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _AudioStateChip(
                  label: source.isMuted ? 'Muted' : 'Live',
                  color: statusTone,
                ),
                if (showDetailedValues) ...<Widget>[
                  const SizedBox(width: 10),
                  Text(
                    source.isMuted
                        ? 'Muted'
                        : hasLiveMeter
                            ? '${source.levelDb.toStringAsFixed(1)} dB'
                            : '-- dB',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _AudioMeterBar(
              level: hasLiveMeter && !source.isMuted ? source.volume : 0,
              color: meterColor,
            ),
            const SizedBox(height: 8),
            Text(
              statusLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _meterColor(BuildContext context) {
    if (source.isMuted) {
      return Theme.of(context).colorScheme.outline;
    }
    if (!metersAvailable || !source.hasLiveMeter) {
      return Theme.of(context).colorScheme.outlineVariant;
    }
    if (source.levelDb >= -6) {
      return Theme.of(context).colorScheme.error;
    }
    if (source.levelDb >= -18) {
      return AppColors.audioOrange;
    }
    return Theme.of(context).colorScheme.primary;
  }

  String _statusLabel(bool hasLiveMeter) {
    if (source.isMuted) return 'Muted in OBS';
    if (!hasLiveMeter) return 'Waiting for OBS audio meter data';
    if (!showDetailedValues) {
      if (source.levelDb <= -45) return 'Quiet';
      if (source.levelDb <= -18) return 'Active';
      return 'Hot';
    }
    return 'Live input meter';
  }
}

class _AudioStateChip extends StatelessWidget {
  const _AudioStateChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _AudioMeterBar extends StatelessWidget {
  const _AudioMeterBar({
    required this.level,
    required this.color,
  });

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 12,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.75),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: level.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  color.withValues(alpha: 0.72),
                  color,
                ],
              ),
            ),
          ),
        ),
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
