import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/utils/obs_qr_payload_parser.dart';
import '../../../../domain/entities/connection_diagnostic.dart';
import '../../../../domain/entities/connection_method.dart';
import '../../../../domain/entities/connection_preflight_report.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/discovered_obs_device.dart';
import '../../../../domain/entities/saved_obs_connection.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/app_section_header.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../../../../shared/widgets/obs_connection_card.dart';
import '../controllers/connection_controller.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _passwordController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _discoveredDevicesKey = GlobalKey();

  bool _connectedSetupExpanded = false;
  bool _manualExpanded = false;
  bool _helpExpanded = false;

  bool get _canScanQr =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    final state = ref.read(connectionControllerProvider);
    _hostController = TextEditingController(text: state.host);
    _portController = TextEditingController(text: state.port);
    _passwordController = TextEditingController(text: state.password);
    ref.listenManual<ConnectionScreenState>(
      connectionControllerProvider,
      (previous, next) {
        final hadDevices = (previous?.discoveredDevices.length ?? 0) > 0;
        final hasDevices = next.discoveredDevices.isNotEmpty;
        final justFoundDevices = !hadDevices && hasDevices;
        final finishedDetecting =
            previous?.isDetecting == true && !next.isDetecting;
        final wasConnected = previous?.status == ConnectionStatus.connected;
        final isConnected = next.status == ConnectionStatus.connected;

        if (!wasConnected && isConnected && mounted) {
          setState(() => _connectedSetupExpanded = false);
        } else if (wasConnected && !isConnected && mounted) {
          setState(() => _connectedSetupExpanded = true);
        }

        if (justFoundDevices || (finishedDetecting && hasDevices)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToDiscoveredDevices();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionControllerProvider);
    final controller = ref.read(connectionControllerProvider.notifier);
    final volunteerMode = ref.watch(volunteerModeProvider);
    final isConnected = state.status == ConnectionStatus.connected;
    final isUsbMode = state.connectionMethod == ConnectionMethod.usb;
    final isManualMode = state.connectionMethod == ConnectionMethod.manual;
    final adbReverseCommand =
        'adb reverse tcp:${int.tryParse(state.port.trim()) ?? 4455} tcp:${int.tryParse(state.port.trim()) ?? 4455}';
    Future<void> onConnectionMethodSelected(ConnectionMethod method) async {
      if (method == ConnectionMethod.manual) {
        setState(() => _manualExpanded = true);
      }
      controller.updateConnectionMethod(method);
      if (method == ConnectionMethod.autoDetect &&
          !state.isBusy &&
          !state.isDetecting) {
        await controller.autoDetect();
      }
    }
    final usbModeCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'USB Mode (No Wi-Fi)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use USB Mode if Wi-Fi is unavailable.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect phone and OBS computer with USB, then use ADB reverse or USB tethering.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '1) Enable USB debugging on Android.\n2) Run on computer:\n$adbReverseCommand\n3) Keep Host as 127.0.0.1 and tap Connect.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: state.isBusy ? null : controller.applyUsbDefaults,
                  icon: const Icon(Icons.usb),
                  label: const Text('Use USB Defaults'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: adbReverseCommand),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('ADB command copied.'),
                          duration: Duration(milliseconds: 1200),
                        ),
                      );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy ADB Command'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Alternative: enable USB tethering and enter your computer USB LAN IP in Host.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
    final autoDetectButton = FilledButton.icon(
      onPressed:
          state.isBusy || state.isDetecting || isUsbMode ? null : controller.autoDetect,
      icon: state.isDetecting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.search),
      label: const Text('Find OBS Automatically'),
    );
    final manualSetupCard = Card(
      child: ExpansionTile(
        key: ValueKey('manual_${isManualMode}_$_manualExpanded'),
        initiallyExpanded: isManualMode || _manualExpanded,
        onExpansionChanged: (expanded) {
          setState(() => _manualExpanded = expanded);
        },
        leading: const Icon(Icons.tune),
        title: const Text('Manual Setup'),
        subtitle: Text(
          isUsbMode ? 'USB host/port/password' : 'Host, port, and password',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: <Widget>[
          if (state.activeAction == ConnectionUiAction.none &&
              (state.status == ConnectionStatus.connecting ||
                  state.status == ConnectionStatus.reconnecting)) ...<Widget>[
            _BackgroundReconnectNotice(status: state.status),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host Address',
              hintText: '192.168.1.10',
              prefixIcon: Icon(Icons.dns_outlined),
              helperText: 'Use the IP address of the computer running OBS.',
            ),
            onChanged: controller.updateHost,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '4455',
                  ),
                  onChanged: controller.updatePort,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Required if configured in OBS',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onChanged: controller.updatePassword,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isBusy ? null : controller.connect,
                  icon: state.isConnectingAction
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy ? null : controller.testConnection,
                  icon: state.isTestingAction
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: const Text('Test'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton.icon(
                  onPressed: state.isBusy ? null : controller.disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: state.isBusy ? null : controller.clearSavedConnection,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Saved'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final setupPanelChildren = <Widget>[
      _ConnectionMethodSelector(
        selected: state.connectionMethod,
        onSelected: onConnectionMethodSelected,
      ),
      if (isManualMode) ...<Widget>[
        const SizedBox(height: 12),
        manualSetupCard,
      ],
      if (isUsbMode) ...<Widget>[
        const SizedBox(height: 12),
        usbModeCard,
      ],
      const SizedBox(height: 14),
      autoDetectButton,
      if (state.isDetecting) ...<Widget>[
        const SizedBox(height: 10),
        const LinearProgressIndicator(minHeight: 3),
        const SizedBox(height: 6),
        Text(
          'Scanning your local network for OBS WebSocket servers...',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
      if (state.discoveredDevices.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        KeyedSubtree(
          key: _discoveredDevicesKey,
          child: _DiscoveredDeviceSection(
            devices: state.discoveredDevices,
            isBusy: state.isBusy,
            onUseDevice: (device) async {
              if (device.requiresPassword && state.password.trim().isEmpty) {
                setState(() => _manualExpanded = true);
              }
              await controller.useDiscoveredDevice(device);
            },
          ),
        ),
      ],
      if (_canScanQr) ...<Widget>[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: state.isBusy || state.isDetecting
              ? null
              : () => _scanQrCode(controller),
          icon: const Icon(Icons.qr_code_scanner_outlined),
          label: const Text('Scan QR Code'),
        ),
      ],
      if (state.savedConnections.isNotEmpty) ...<Widget>[
        const SizedBox(height: 14),
        _SavedConnectionsSection(
          connections: state.savedConnections,
          busy: state.isBusy,
          onConnect: controller.connectToSaved,
          onDelete: controller.removeSavedConnection,
        ),
      ],
      if (!isManualMode) ...<Widget>[
        const SizedBox(height: 14),
        manualSetupCard,
      ],
    ];

    _syncControllerText(_hostController, state.host);
    _syncControllerText(_portController, state.port);
    _syncControllerText(_passwordController, state.password);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/controller'),
        title: const BrandAppBarTitle(title: 'DeckPilot for OBS'),
        actions: <Widget>[
          _ConnectionHeaderChip(
            status: state.status,
            latencyMs: state.latencyMs,
          ),
          IconButton(
            tooltip: 'Back to controller',
            onPressed: () => context.go('/controller'),
            icon: const Icon(Icons.dashboard_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: volunteerMode
            ? _VolunteerModeLockedState(status: state)
            : ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  const BrandConnectHeader(),
                  const SizedBox(height: 10),
                  const AppSectionHeader(
                    title: 'Connect to OBS',
                    subtitle:
                        'Connect this device to the computer running OBS. Both devices must be on the same Wi-Fi or hotspot network.',
                  ),
                  const SizedBox(height: 12),
                  if (isConnected)
                    _ConnectedObsSetupPanel(
                      expanded: _connectedSetupExpanded,
                      latencyMs: state.latencyMs,
                      onExpansionChanged: (expanded) {
                        setState(() => _connectedSetupExpanded = expanded);
                      },
                      children: setupPanelChildren,
                    )
                  else ...<Widget>[
                    _BeforeConnectingSection(
                      emphasized: state.showSetupGuide,
                      onViewGuide: () => _showSetupGuide(context, controller),
                    ),
                    const SizedBox(height: 12),
                    ...setupPanelChildren,
                    const SizedBox(height: 12),
                    ObsConnectionCard(
                      status: state.status,
                      message: state.statusMessage,
                      latencyMs: state.latencyMs,
                    ),
                  ],
                  if (!isConnected &&
                      !isManualMode &&
                      state.preflight != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _NetworkCheckCard(
                      report: state.preflight!,
                      host: state.host,
                      port: state.port,
                      method: state.connectionMethod,
                    ),
                  ],
                  if (!isConnected &&
                      !isManualMode &&
                      state.diagnostics.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _DiagnosticsSection(diagnostics: state.diagnostics),
                  ],
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: <Widget>[
                        SwitchListTile.adaptive(
                          value: state.autoReconnect,
                          title: const Text('Reconnect after disconnect'),
                          subtitle: const Text(
                            'Retry automatically only if OBS disconnects after a successful connection.',
                          ),
                          onChanged: controller.updateAutoReconnect,
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          value: state.rememberConnectionInfo,
                          title: const Text('Remember connection info'),
                          subtitle: const Text(
                            'Save successful connections for quick reconnect.',
                          ),
                          onChanged: controller.updateRememberConnectionInfo,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: _helpExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() => _helpExpanded = expanded);
                      },
                      leading: const Icon(Icons.help_outline),
                      title: const Text('Having trouble connecting?'),
                      subtitle: const Text('Show network tips'),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      children: <Widget>[
                        Text(
                          'Your phone and OBS computer should usually be on the same Wi-Fi or hotspot.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use the computer local IP address in Host, not 127.0.0.1 on the phone.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (defaultTargetPlatform == TargetPlatform.android)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Android emulator shortcut: use 10.0.2.2 for OBS running on your computer.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Find IP: Windows ipconfig • macOS/Linux ifconfig (or network settings).',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.settings,
      ),
    );
  }

  void _syncControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _scrollToDiscoveredDevices() async {
    final context = _discoveredDevicesKey.currentContext;
    if (context == null || !_scrollController.hasClients) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  Future<void> _showSetupGuide(
    BuildContext context,
    ConnectionController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ObsSetupGuideSheet(),
    );
    await controller.dismissSetupGuide();
  }

  Future<void> _scanQrCode(ConnectionController controller) async {
    final rawPayload = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _QrScanSheet(),
    );

    if (!mounted || rawPayload == null) return;

    try {
      final payload = ObsQrPayloadParser.parse(rawPayload);
      controller.applyScannedConnection(
        host: payload.host,
        port: payload.port,
        password: payload.password,
        label: payload.label,
      );

      final shouldConnect = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('QR loaded'),
            content: Text(
              payload.label == null
                  ? 'Connect to ${payload.host}:${payload.port} now?'
                  : 'Connect to ${payload.label} (${payload.host}:${payload.port}) now?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Connect'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;
      if (shouldConnect == true) {
        await controller.connect();
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      final message = error.message.toString().trim();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              message.isEmpty ? 'Invalid OBS QR payload.' : message,
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    }
  }
}

class _BackgroundReconnectNotice extends StatelessWidget {
  const _BackgroundReconnectNotice({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = status == ConnectionStatus.reconnecting
        ? Colors.orange
        : colorScheme.primary;
    final title = status == ConnectionStatus.reconnecting
        ? 'Background reconnect in progress'
        : 'Background connection in progress';
    final body = status == ConnectionStatus.reconnecting
        ? 'DeckPilot is retrying your saved OBS connection. You can wait, or edit the details below and connect manually.'
        : 'DeckPilot is trying a saved OBS connection in the background. You can wait, or edit the details below and connect manually.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.sync, color: tone, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tone,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionHeaderChip extends StatelessWidget {
  const _ConnectionHeaderChip({
    required this.status,
    this.latencyMs,
  });

  final ConnectionStatus status;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting ||
      ConnectionStatus.reconnecting =>
        Colors.orange,
      ConnectionStatus.wrongPassword ||
      ConnectionStatus.notFound ||
      ConnectionStatus.error =>
        Theme.of(context).colorScheme.error,
      ConnectionStatus.disconnected => Theme.of(context).colorScheme.outline,
    };
    final label = switch (status) {
      ConnectionStatus.connected => latencyMs == null ? 'OBS' : '$latencyMs ms',
      ConnectionStatus.connecting => '...',
      ConnectionStatus.reconnecting => 'Retry',
      ConnectionStatus.wrongPassword => 'Auth',
      ConnectionStatus.notFound => 'Net',
      ConnectionStatus.error => 'Err',
      ConnectionStatus.disconnected => 'Off',
    };

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tone,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedObsSetupPanel extends StatelessWidget {
  const _ConnectedObsSetupPanel({
    required this.expanded,
    required this.onExpansionChanged,
    required this.children,
    this.latencyMs,
  });

  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final List<Widget> children;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    const tone = Colors.green;

    return Card(
      child: ExpansionTile(
        key: ValueKey('connected_setup_$expanded-${latencyMs ?? 'na'}'),
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: tone,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          'OBS Connected',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        subtitle: Text(
          expanded
              ? 'Connection settings'
              : 'Tap to expand connection settings',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (latencyMs != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$latencyMs ms',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _BeforeConnectingSection extends StatelessWidget {
  const _BeforeConnectingSection({
    required this.emphasized,
    required this.onViewGuide,
  });

  final bool emphasized;
  final Future<void> Function() onViewGuide;

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.primary;
    final steps = <String>[
      'Open OBS Studio',
      'Click Tools',
      'Select WebSocket Server Settings',
      'Enable WebSocket Server',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.playlist_add_check_circle_outlined,
                  color: emphasized ? tone : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Before Connecting',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (emphasized)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'REQUIRED',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tone,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'OBS must have its WebSocket server enabled before DeckPilot can connect.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            ...List<Widget>.generate(
              steps.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(steps[index])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onViewGuide,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('View Setup Guide'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObsSetupGuideSheet extends StatelessWidget {
  const _ObsSetupGuideSheet();

  @override
  Widget build(BuildContext context) {
    const steps = <({String title, String body, IconData icon})>[
      (
        title: 'Step 1',
        body: 'Open OBS and click Tools.',
        icon: Icons.video_settings,
      ),
      (
        title: 'Step 2',
        body: 'Click WebSocket Server Settings.',
        icon: Icons.settings_ethernet,
      ),
      (
        title: 'Step 3',
        body: 'Enable WebSocket Server and keep port 4455.',
        icon: Icons.toggle_on,
      ),
      (
        title: 'Step 4',
        body: 'Return to DeckPilot and tap Find OBS Automatically.',
        icon: Icons.search,
      ),
    ];

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.86,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.26),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'OBS Setup Guide',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                'OBS must expose its WebSocket server before DeckPilot can detect or connect to it.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                itemCount: steps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final step = steps[index];
                  return _SetupGuideStepCard(
                    stepNumber: index + 1,
                    title: step.title,
                    body: step.body,
                    icon: step.icon,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupGuideStepCard extends StatelessWidget {
  const _SetupGuideStepCard({
    required this.stepNumber,
    required this.title,
    required this.body,
    required this.icon,
  });

  final int stepNumber;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$stepNumber',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.8),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: tone, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkCheckCard extends StatelessWidget {
  const _NetworkCheckCard({
    required this.report,
    required this.host,
    required this.port,
    required this.method,
  });

  final ConnectionPreflightReport report;
  final String host;
  final String port;
  final ConnectionMethod method;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];

    if (method == ConnectionMethod.usb) {
      items.add('USB mode selected');
      items.add('ADB reverse or USB LAN is required');
    } else {
      items.add(report.hasLocalNetwork
          ? 'Local network detected'
          : 'No local Wi-Fi/hotspot detected');
      if (host.trim().isNotEmpty) {
        items.add(report.hostResolved
            ? 'Host resolves: ${host.trim()}'
            : 'Host could not be resolved');
      }
      if (report.hostIsPrivateIpv4) {
        items.add(
          report.likelySameSubnet
              ? 'Likely same subnet as this device'
              : 'Host may be on a different subnet',
        );
      }
      if (host.trim().isNotEmpty && port.trim().isNotEmpty) {
        items.add(report.portOpen
            ? 'TCP port ${port.trim()} responded'
            : 'No TCP response from ${host.trim()}:${port.trim()}');
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Network Check',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      item.startsWith('No ') || item.contains('different')
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 18,
                      color:
                          item.startsWith('No ') || item.contains('different')
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (report.localAddresses.isNotEmpty &&
                method != ConnectionMethod.usb)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Device IPs: ${report.localAddresses.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.diagnostics});

  final List<ConnectionDiagnostic> diagnostics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Connection Diagnostics',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ...diagnostics.map(
              (diagnostic) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DiagnosticTile(diagnostic: diagnostic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile({required this.diagnostic});

  final ConnectionDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = switch (diagnostic.severity) {
      ConnectionDiagnosticSeverity.info => scheme.primary,
      ConnectionDiagnosticSeverity.warning => Colors.orange,
      ConnectionDiagnosticSeverity.error => scheme.error,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            switch (diagnostic.severity) {
              ConnectionDiagnosticSeverity.info => Icons.info_outline,
              ConnectionDiagnosticSeverity.warning =>
                Icons.warning_amber_rounded,
              ConnectionDiagnosticSeverity.error => Icons.error_outline,
            },
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  diagnostic.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  diagnostic.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  diagnostic.fix,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionMethodSelector extends StatelessWidget {
  const _ConnectionMethodSelector({
    required this.selected,
    required this.onSelected,
  });

  final ConnectionMethod selected;
  final ValueChanged<ConnectionMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Connection Method',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ConnectionMethod.values.map((method) {
                final active = method == selected;
                return ChoiceChip(
                  selected: active,
                  onSelected: (_) => onSelected(method),
                  avatar: Icon(
                    _iconForMethod(method),
                    size: 18,
                    color: active
                        ? selectedColor
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: Text(method.label),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 8),
            Text(
              selected.helper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForMethod(ConnectionMethod method) {
    switch (method) {
      case ConnectionMethod.autoDetect:
        return Icons.search;
      case ConnectionMethod.wifi:
        return Icons.wifi;
      case ConnectionMethod.usb:
        return Icons.usb;
      case ConnectionMethod.manual:
        return Icons.tune;
    }
  }
}

class _VolunteerModeLockedState extends StatelessWidget {
  const _VolunteerModeLockedState({required this.status});

  final ConnectionScreenState status;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const BrandConnectHeader(),
        const SizedBox(height: 12),
        const AppSectionHeader(
          title: 'OBS Connection',
          subtitle: 'Connection controls are disabled in Volunteer Mode.',
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Advanced controls disabled'),
            subtitle: Text(
              'Disable Volunteer Mode in Settings to edit OBS connection or disconnect.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        ObsConnectionCard(
          status: status.status,
          message: status.statusMessage,
          latencyMs: status.latencyMs,
        ),
      ],
    );
  }
}

class _DiscoveredDeviceSection extends StatelessWidget {
  const _DiscoveredDeviceSection({
    required this.devices,
    required this.isBusy,
    required this.onUseDevice,
  });

  final List<DiscoveredObsDevice> devices;
  final bool isBusy;
  final ValueChanged<DiscoveredObsDevice> onUseDevice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Discovered OBS Devices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a device to connect quickly.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            ...devices.map(
              (device) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  device.requiresPassword
                      ? Icons.lock_outline
                      : Icons.wifi_tethering,
                ),
                title: Text('OBS Studio (${device.host})'),
                subtitle: Text(
                  device.requiresPassword
                      ? 'Port ${device.port} • Password required'
                      : 'Port ${device.port}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: isBusy ? null : () => onUseDevice(device),
                  child: const Text('Connect'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedConnectionsSection extends StatelessWidget {
  const _SavedConnectionsSection({
    required this.connections,
    required this.busy,
    required this.onConnect,
    required this.onDelete,
  });

  final List<SavedObsConnection> connections;
  final bool busy;
  final ValueChanged<SavedObsConnection> onConnect;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Saved Connections',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ...connections.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(item.label),
                subtitle: Text('${item.host}:${item.port}'),
                trailing: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: busy ? null : () => onDelete(item.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    FilledButton.tonal(
                      onPressed: busy ? null : () => onConnect(item),
                      child: const Text('Reconnect'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrScanSheet extends StatefulWidget {
  const _QrScanSheet();

  @override
  State<_QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<_QrScanSheet> {
  late final MobileScannerController _scannerController;
  bool _handledResult = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Scan OBS QR Code',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Supported QR formats: obs://host=192.168.1.23&port=4455&password=... or JSON with host/port/password.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handledResult) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _handledResult = true;
      _scannerController.stop();
      Navigator.of(context).pop(value);
      return;
    }
  }
}
