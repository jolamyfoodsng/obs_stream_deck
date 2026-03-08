import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/layout_preset.dart';
import '../../../../domain/entities/scene_preview_mode.dart';
import '../../../../domain/entities/obs_connection_config.dart';
import '../../../controller/presentation/controllers/controller_controller.dart';
import '../../../page_manager/presentation/controllers/page_manager_controller.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../../../../shared/widgets/app_section_header.dart';

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
      _loadingConnectionPrefs = false;
    });
  }

  Future<void> _saveConnectionPrefs() async {
    final repository = ref.read(connectionRepositoryProvider);
    final current = await repository.loadConfig();

    final next = (current ??
            const ObsConnectionConfig(
              host: '127.0.0.1',
              port: 4455,
              password: '',
            ))
        .copyWith(
      autoReconnect: _autoReconnect,
      rememberConnectionInfo: _rememberConnectionInfo,
    );

    if (_rememberConnectionInfo) {
      await repository.saveConfig(next);
    } else {
      await repository.clearConfig();
    }
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

  @override
  Widget build(BuildContext context) {
    final volunteerMode = ref.watch(volunteerModeProvider);
    final scenePreviewMode = ref.watch(scenePreviewModeProvider);
    final scenePreviewEnabled = scenePreviewMode != ScenePreviewMode.off;
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
                                  (mode) => DropdownMenuItem<ScenePreviewMode>(
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
            const AppSectionHeader(title: 'OBS Connection'),
            const SizedBox(height: 10),
            if (volunteerMode)
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
                      title: const Text('Auto reconnect'),
                      subtitle:
                          const Text('Reconnect automatically after drop.'),
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
            const SizedBox(height: 10),
            const AppSectionHeader(title: 'Help & Onboarding'),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.star_rate_outlined),
                    title: const Text('Rate DeckPilot'),
                    subtitle: const Text('Leave feedback in the app store.'),
                    onTap: _rateDeckPilot,
                  ),
                  const Divider(height: 1),
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
                  const Divider(height: 1),
                  const ExpansionTile(
                    leading: Icon(Icons.help_outline),
                    title: Text('How to connect to OBS'),
                    childrenPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Use Find OBS Automatically first. If nothing is found, scan a QR or use Manual Setup with your computer local IP and OBS password.',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const ExpansionTile(
                    leading: Icon(Icons.qr_code_scanner_outlined),
                    title: Text('How QR connect works'),
                    childrenPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Scan a QR payload containing host, port, and password. The app auto-fills details and can connect immediately after confirmation.',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const ExpansionTile(
                    leading: Icon(Icons.wifi_tethering),
                    title: Text('Same Wi-Fi / hotspot requirement'),
                    childrenPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Your phone and OBS computer should usually be on the same Wi-Fi or hotspot network. 127.0.0.1 on a phone points to the phone itself, not your OBS computer.',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const ExpansionTile(
                    leading: Icon(Icons.bolt_outlined),
                    title: Text('How macros work'),
                    childrenPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Macros run multiple OBS actions in sequence. You can create, test, duplicate, and assign macros to controller buttons.',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const ExpansionTile(
                    leading: Icon(Icons.volunteer_activism_outlined),
                    title: Text('What Volunteer Mode does'),
                    childrenPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Volunteer Mode hides advanced and dangerous controls so operators can safely run approved actions.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
