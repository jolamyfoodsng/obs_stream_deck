import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../domain/entities/layout_preset.dart';
import '../../../../domain/entities/premium_feature.dart';
import '../../../../domain/entities/quick_control.dart';
import '../../../../domain/entities/scene_preview_mode.dart';
import '../../../controller/presentation/controllers/controller_controller.dart';
import '../../../page_manager/presentation/controllers/page_manager_controller.dart';
import '../../../../shared/state/app_engagement_controller.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/state/quick_controls_settings_controller.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../../../../shared/widgets/app_section_header.dart';
import '../../../../shared/widgets/premium_upgrade_modal.dart';
import '../../../../shared/widgets/pro_badge.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _haptics = true;
  bool _animations = true;

  bool _autoReconnect = true;
  bool _rememberConnectionInfo = true;
  bool _loadingConnectionPrefs = true;

  List<LayoutPreset> _presets = const <LayoutPreset>[];
  bool _loadingPresets = true;
  String? _selectedPresetId;

  @override
  void initState() {
    super.initState();
    _loadConnectionPrefs();
    _loadPresets();
  }

  Future<void> _loadConnectionPrefs() async {
    final repository = ref.read(connectionRepositoryProvider);
    final storage = ref.read(localStorageServiceProvider);
    final config = await repository.loadConfig();
    if (!mounted) return;

    if (config != null) {
      setState(() {
        _autoReconnect = config.autoReconnect;
        _rememberConnectionInfo = config.rememberConnectionInfo;
        _loadingConnectionPrefs = false;
      });
      return;
    }

    setState(() {
      _autoReconnect =
          storage.getBool(StorageKeys.connectionAutoReconnectPref) ?? true;
      _rememberConnectionInfo =
          storage.getBool(StorageKeys.connectionRememberInfoPref) ?? true;
      _loadingConnectionPrefs = false;
    });
  }

  Future<void> _saveConnectionPrefs() async {
    final repository = ref.read(connectionRepositoryProvider);
    final storage = ref.read(localStorageServiceProvider);
    final obsRepository = ref.read(obsRepositoryProvider);
    final current = await repository.loadConfig();

    await storage.setBool(
      StorageKeys.connectionAutoReconnectPref,
      _autoReconnect,
    );
    await storage.setBool(
      StorageKeys.connectionRememberInfoPref,
      _rememberConnectionInfo,
    );

    if (!_rememberConnectionInfo) {
      await repository.clearConfig();
    } else if (current != null) {
      final next = current.copyWith(
        autoReconnect: _autoReconnect,
        rememberConnectionInfo: _rememberConnectionInfo,
      );
      await repository.saveConfig(next);
    }

    obsRepository.updateConnectionPreferences(
      autoReconnect: _autoReconnect,
      rememberConnectionInfo: _rememberConnectionInfo,
    );
  }

  Future<void> _loadPresets() async {
    final presets = await ref.read(layoutPresetServiceProvider).loadPresets();
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _loadingPresets = false;
      if (_selectedPresetId != null &&
          !presets.any((preset) => preset.id == _selectedPresetId)) {
        _selectedPresetId = null;
      }
    });
  }

  Future<void> _clearSavedConfig() async {
    await ref.read(connectionRepositoryProvider).clearConfig();
    if (!mounted) return;

    setState(() {
      _rememberConnectionInfo = false;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Saved OBS connection has been cleared.')),
      );
  }

  Future<void> _exportLayoutJson() async {
    final json =
        await ref.read(layoutPresetServiceProvider).exportCurrentLayoutJson();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export Layout JSON'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(json),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: json));
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Layout JSON copied to clipboard.'),
                    ),
                  );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importLayoutJson() async {
    final controller = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import Layout JSON'),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: controller,
              maxLines: 14,
              minLines: 8,
              decoration: const InputDecoration(
                hintText: 'Paste exported JSON here',
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      controller.dispose();
      return;
    }

    try {
      await ref.read(layoutPresetServiceProvider).importLayoutJson(
            controller.text.trim(),
          );
      if (!mounted) return;
      await _afterLayoutMutation(
        message: 'Layout imported successfully.',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Import failed: ${error.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _saveAsPreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save Preset'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              hintText: 'e.g. Sunday Service',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                controller.text.trim(),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(layoutPresetServiceProvider)
        .saveCurrentAsPreset(name.trim());
    await _loadPresets();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Preset "$name" saved.')),
      );
  }

  Future<void> _applySelectedPreset() async {
    final presetId = _selectedPresetId;
    if (presetId == null || presetId.isEmpty) return;

    await ref.read(layoutPresetServiceProvider).applyPreset(presetId);
    await _afterLayoutMutation(message: 'Preset applied.');
  }

  Future<void> _deleteSelectedPreset() async {
    final presetId = _selectedPresetId;
    if (presetId == null || presetId.isEmpty) return;

    await ref.read(layoutPresetServiceProvider).deletePreset(presetId);
    await _loadPresets();
    if (!mounted) return;
    setState(() => _selectedPresetId = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Preset deleted.')),
      );
  }

  Future<void> _afterLayoutMutation({required String message}) async {
    await _loadConnectionPrefs();
    await _loadPresets();
    ref.invalidate(controllerControllerProvider);
    ref.invalidate(pageManagerControllerProvider);
    ref.invalidate(volunteerModeProvider);
    ref.invalidate(scenePreviewModeProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rateDeckPilot() async {
    final requested = await ref
        .read(appEngagementControllerProvider.notifier)
        .requestManualReview();
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            requested
                ? 'Thanks for rating DeckPilot.'
                : 'Unable to open review right now. Please try again later.',
          ),
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  Future<void> _showTutorialAgain() async {
    await ref
        .read(appEngagementControllerProvider.notifier)
        .requestTutorialReplay();
    if (!mounted) return;
    context.go('/controller');
  }

  Future<void> _showSupportDialog() async {
    final runtime = ref.read(obsRepositoryProvider).currentState();
    final connectionConfig =
        await ref.read(connectionRepositoryProvider).loadConfig();
    if (!mounted) return;

    final connectionSummary = connectionConfig == null
        ? 'No saved OBS connection'
        : '${connectionConfig.host}:${connectionConfig.port} • ${runtime.connectionStatus.name}';
    final message = [
      'DeckPilot Support',
      'Describe what went wrong, what screen you were on, and what you expected to happen.',
      '',
      'Include this if you contact support:',
      'OBS: $connectionSummary',
      'Stream: ${runtime.streamStatus.name}',
      'Recording: ${runtime.recordingStatus.name}',
    ].join('\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Contact Support'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Need help or want to report a problem?',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Copy the support note below and send it with your issue details.',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(message),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Support note copied to clipboard.'),
                    ),
                  );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy Note'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildFaqSection(AppEngagementState engagement) {
    const divider = Divider(height: 1);
    return <Widget>[
      const AppSectionHeader(title: 'Help & FAQ'),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Show Tutorial Again'),
              subtitle: Text(
                engagement.tutorialCompleted
                    ? 'Replay the guided walkthrough.'
                    : 'Show the first-time walkthrough.',
              ),
              onTap: _showTutorialAgain,
            ),
            divider,
            ListTile(
              leading: const Icon(Icons.star_rate_outlined),
              title: const Text('Rate DeckPilot'),
              subtitle: const Text('Leave feedback in the app store.'),
              onTap: _rateDeckPilot,
            ),
            divider,
            const _FaqTile(
              icon: Icons.link_outlined,
              title: 'How to connect to OBS',
              answer:
                  'Open OBS on your computer, enable WebSocket Server in Tools, then use Find OBS Automatically first. If needed, scan a QR code or enter the computer IP manually.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.search_off_outlined,
              title: 'Why OBS is not found',
              answer:
                  'OBS may be closed, WebSocket may be disabled, the port may be wrong, or both devices may not be on the same local network.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.phonelink_lock_outlined,
              title: 'Why 127.0.0.1 does not work on phone',
              answer:
                  'On a phone, 127.0.0.1 points back to the phone itself. Use the local IP address of the computer running OBS instead.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.wifi_tethering_outlined,
              title: 'Do both devices need the same Wi-Fi or hotspot?',
              answer:
                  'Usually yes. Your phone and the OBS computer should be on the same Wi-Fi or hotspot so they can reach each other directly.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.usb_outlined,
              title: 'How USB mode works',
              answer:
                  'USB mode is for cases where Wi-Fi is unavailable. It works through ADB reverse or a USB network/tethering connection so the phone can reach OBS locally.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.qr_code_scanner_outlined,
              title: 'How QR connect works',
              answer:
                  'Scan a QR code that contains the OBS host, port, and password. DeckPilot fills the details for you so you do not need to type them.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.bolt_outlined,
              title: 'How macros work',
              answer:
                  'Macros let one button run several OBS actions in order, such as switching scene, waiting, then starting stream or recording.',
            ),
            divider,
            const _FaqTile(
              icon: Icons.workspace_premium_outlined,
              title: 'What Premium unlocks',
              answer:
                  'Premium unlocks unlimited pages and scene buttons, more macro power, scene previews, stream monitoring, and emergency controls.',
            ),
            divider,
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Contact Support / Send Feedback'),
              subtitle: const Text('Copy a support note and report a problem.'),
              onTap: _showSupportDialog,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildObsConnectionSection() {
    return <Widget>[
      const AppSectionHeader(title: 'OBS Connection'),
      const SizedBox(height: 10),
      if (ref.watch(volunteerModeProvider))
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Connection settings hidden'),
            subtitle: Text(
              'Disable Volunteer Mode to manage OBS connection settings.',
            ),
            onTap: null,
          ),
        )
      else if (_loadingConnectionPrefs)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile.adaptive(
                value: _autoReconnect,
                title: const Text('Reconnect after disconnect'),
                subtitle: const Text(
                  'Retry automatically only if OBS disconnects after a successful connection.',
                ),
                onChanged: (value) async {
                  setState(() => _autoReconnect = value);
                  await _saveConnectionPrefs();
                },
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _rememberConnectionInfo,
                title: const Text('Remember connection info'),
                subtitle: const Text('Persist OBS host/port/password.'),
                onChanged: (value) async {
                  setState(() => _rememberConnectionInfo = value);
                  await _saveConnectionPrefs();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Clear saved connection'),
                subtitle: const Text('Remove saved OBS host/password.'),
                onTap: _clearSavedConfig,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Open connection screen'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/connection'),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildQuickControlsSection({
    required bool isPremium,
    required QuickControlsSettings quickControls,
  }) {
    return <Widget>[
      const AppSectionHeader(
        title: 'Quick Controls',
        subtitle: 'Manage the top control buttons shown on the Control screen.',
      ),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: <Widget>[
            if (isPremium)
              ...QuickControlId.values.asMap().entries.expand((entry) {
                final index = entry.key;
                final control = entry.value;
                final enabled = quickControls.enabledControls.contains(control);
                return <Widget>[
                  SwitchListTile.adaptive(
                    value: enabled,
                    title: Text(control.settingsLabel),
                    subtitle: Text(control.settingsDescription),
                    secondary: Icon(_quickControlIcon(control)),
                    onChanged: (value) async {
                      await ref
                          .read(quickControlsSettingsProvider.notifier)
                          .setEnabled(control, value);
                    },
                  ),
                  if (index != QuickControlId.values.length - 1)
                    const Divider(height: 1),
                ];
              })
            else ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Free plan uses the default quick controls. Upgrade to Premium to hide controls or add extra quick actions.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              ...QuickControlId.values.asMap().entries.expand((entry) {
                final index = entry.key;
                final control = entry.value;
                final isLocked = control.premiumOnly;
                return <Widget>[
                  ListTile(
                    leading: Icon(_quickControlIcon(control)),
                    title: Row(
                      children: <Widget>[
                        Expanded(child: Text(control.settingsLabel)),
                        if (isLocked) const ProBadge(compact: true),
                      ],
                    ),
                    subtitle: Text(
                      isLocked
                          ? '${control.settingsDescription} Premium only.'
                          : '${control.settingsDescription} Included in Free.',
                    ),
                    trailing: Icon(
                      isLocked
                          ? Icons.lock_outline
                          : Icons.check_circle_outline,
                    ),
                    onTap: isLocked
                        ? () => showPremiumUpgradeModal(
                              context,
                              highlightedFeature:
                                  PremiumFeature.advancedAutomation,
                            )
                        : null,
                  ),
                  if (index != QuickControlId.values.length - 1)
                    const Divider(height: 1),
                ];
              }),
            ],
          ],
        ),
      ),
    ];
  }

  IconData _quickControlIcon(QuickControlId control) {
    switch (control) {
      case QuickControlId.muteMic:
        return Icons.mic_off_outlined;
      case QuickControlId.stream:
        return Icons.stream_outlined;
      case QuickControlId.recording:
        return Icons.fiber_manual_record;
      case QuickControlId.virtualCamera:
        return Icons.videocam_outlined;
      case QuickControlId.studioMode:
        return Icons.slideshow_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final volunteerMode = ref.watch(volunteerModeProvider);
    final premium = ref.watch(premiumControllerProvider);
    final quickControls = ref.watch(quickControlsSettingsProvider);
    final scenePreviewMode = ref.watch(scenePreviewModeProvider);
    final scenePreviewEnabled =
        premium.isPremium && scenePreviewMode != ScenePreviewMode.off;
    final engagement = ref.watch(appEngagementControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const BrandAppBarTitle(title: 'DeckPilot'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const AppSectionHeader(title: 'General'),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    value: volunteerMode,
                    onChanged: (value) async {
                      await ref
                          .read(volunteerModeProvider.notifier)
                          .setEnabled(value);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              value
                                  ? 'Volunteer Mode enabled. Advanced controls are disabled.'
                                  : 'Volunteer Mode disabled. Full controls are enabled.',
                            ),
                            duration: const Duration(milliseconds: 1600),
                          ),
                        );
                    },
                    title: const Text('Enable Volunteer Mode'),
                    subtitle: Text(
                      volunteerMode
                          ? 'Active now: advanced controls are disabled.'
                          : 'Off now: full controls are available.',
                    ),
                  ),
                  const Divider(height: 1),
                  if (premium.isPremium) ...<Widget>[
                    SwitchListTile.adaptive(
                      value: scenePreviewEnabled,
                      title: const Text('Enable Scene Previews'),
                      subtitle: Text(
                        scenePreviewEnabled
                            ? 'On: scene snapshots are shown.'
                            : 'Off: no scene preview images are loaded.',
                      ),
                      onChanged: (enabled) async {
                        final nextMode = enabled
                            ? (scenePreviewMode == ScenePreviewMode.off
                                ? ScenePreviewMode.staticThumbnails
                                : scenePreviewMode)
                            : ScenePreviewMode.off;
                        await ref
                            .read(scenePreviewModeProvider.notifier)
                            .setMode(nextMode);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                enabled
                                    ? 'Scene previews enabled.'
                                    : 'Scene previews disabled.',
                              ),
                              duration: const Duration(milliseconds: 1400),
                            ),
                          );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (scenePreviewEnabled) ...<Widget>[
                            Text(
                              'Snapshot-based previews only. No live thumbnail streaming.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<ScenePreviewMode>(
                              initialValue: scenePreviewMode,
                              decoration: const InputDecoration(
                                labelText: 'Preview behavior',
                              ),
                              items: const <ScenePreviewMode>[
                                ScenePreviewMode.staticThumbnails,
                                ScenePreviewMode.autoRefresh10s,
                                ScenePreviewMode.tapToRefresh,
                              ]
                                  .map(
                                    (mode) =>
                                        DropdownMenuItem<ScenePreviewMode>(
                                      value: mode,
                                      child: Text(mode.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (mode) async {
                                if (mode == null) return;
                                await ref
                                    .read(scenePreviewModeProvider.notifier)
                                    .setMode(mode);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Scene Preview Mode set to ${mode.label}.',
                                      ),
                                      duration:
                                          const Duration(milliseconds: 1400),
                                    ),
                                  );
                              },
                            ),
                          ] else ...<Widget>[
                            Text(
                              'Enable this to display scene snapshots on scene buttons.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...<Widget>[
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Row(
                        children: <Widget>[
                          Expanded(child: Text('Scene Preview Thumbnails')),
                          ProBadge(compact: true),
                        ],
                      ),
                      subtitle: const Text(
                        'Unlock static scene snapshots and refresh modes.',
                      ),
                      trailing: const Icon(Icons.lock_outline),
                      onTap: () => showPremiumUpgradeModal(
                        context,
                        highlightedFeature: PremiumFeature.scenePreviews,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            ..._buildObsConnectionSection(),
            const SizedBox(height: 10),
            ..._buildQuickControlsSection(
              isPremium: premium.isPremium,
              quickControls: quickControls,
            ),
            const SizedBox(height: 10),
            const AppSectionHeader(title: 'Premium'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: premium.isPremium
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Text(
                                'DeckPilot Premium',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.verified,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Activated',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Thank you for supporting DeckPilot.',
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'DeckPilot Premium',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              ProBadge(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Unlock the full power of OBS control.'),
                          const SizedBox(height: 10),
                          const _PremiumBullet(text: 'Unlimited pages'),
                          const _PremiumBullet(text: 'Unlimited scene buttons'),
                          const _PremiumBullet(text: 'Macros'),
                          const _PremiumBullet(text: 'Scene previews'),
                          const _PremiumBullet(text: 'Stream monitoring'),
                          const _PremiumBullet(text: 'Emergency controls page'),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => showPremiumUpgradeModal(
                                context,
                                highlightedFeature: PremiumFeature.macros,
                              ),
                              child: Text(
                                'Upgrade to Premium — ${premium.productPrice}',
                              ),
                            ),
                          ),
                          if ((premium.error ?? '').trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              premium.error!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            if (!premium.isPremium) ...<Widget>[
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.auto_mode_outlined),
                      title: const Row(
                        children: <Widget>[
                          Expanded(child: Text('Advanced Automation')),
                          ProBadge(compact: true),
                        ],
                      ),
                      subtitle: const Text(
                        'Build richer control flows and automation recipes.',
                      ),
                      trailing: const Icon(Icons.lock_outline),
                      onTap: () => showPremiumUpgradeModal(
                        context,
                        highlightedFeature: PremiumFeature.advancedAutomation,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.public_outlined),
                      title: const Row(
                        children: <Widget>[
                          Expanded(
                              child: Text('Internet Remote (Coming Soon)')),
                          ProBadge(compact: true),
                        ],
                      ),
                      subtitle: const Text(
                        'Control OBS remotely over the internet when available.',
                      ),
                      trailing: const Icon(Icons.lock_outline),
                      onTap: () => showPremiumUpgradeModal(
                        context,
                        highlightedFeature: PremiumFeature.internetRemote,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            const AppSectionHeader(title: 'Performance'),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    value: _haptics,
                    onChanged: (value) => setState(() => _haptics = value),
                    title: const Text('Haptics'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _animations,
                    onChanged: (value) => setState(() => _animations = value),
                    title: const Text('Animations'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const AppSectionHeader(title: 'Layouts & Presets'),
            const SizedBox(height: 10),
            if (volunteerMode)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Layout tools hidden'),
                  subtitle: Text(
                    'Disable Volunteer Mode to import/export or manage presets.',
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('Export layout JSON'),
                      subtitle: const Text(
                          'Export pages, buttons, macros and settings.'),
                      onTap: _exportLayoutJson,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Import layout JSON'),
                      subtitle:
                          const Text('Import and replace current layout.'),
                      onTap: _importLayoutJson,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.save_as_outlined),
                      title: const Text('Save current as preset'),
                      onTap: _saveAsPreset,
                    ),
                    const Divider(height: 1),
                    if (_loadingPresets)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      )
                    else if (_presets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No presets saved yet.'),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Column(
                          children: <Widget>[
                            DropdownButtonFormField<String>(
                              initialValue: _selectedPresetId,
                              decoration: const InputDecoration(
                                  labelText: 'Select preset'),
                              items: _presets
                                  .map(
                                    (preset) => DropdownMenuItem<String>(
                                      value: preset.id,
                                      child: Text(preset.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedPresetId = value);
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedPresetId == null
                                        ? null
                                        : _applySelectedPreset,
                                    icon: const Icon(Icons.playlist_add_check),
                                    label: const Text('Apply'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedPresetId == null
                                        ? null
                                        : _deleteSelectedPreset,
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Delete'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            ..._buildFaqSection(engagement),
            const SizedBox(height: 18),
            Text(
              'App Version 1.0.0',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.settings,
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.icon,
    required this.title,
    required this.answer,
  });

  final IconData icon;
  final String title;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          answer,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _PremiumBullet extends StatelessWidget {
  const _PremiumBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.check_circle,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
