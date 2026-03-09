import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/utils/obs_qr_payload_parser.dart';
import '../../../../domain/entities/connection_method.dart';
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
  }

  @override
  void dispose() {
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
    final isUsbMode = state.connectionMethod == ConnectionMethod.usb;
    final adbReverseCommand =
        'adb reverse tcp:${int.tryParse(state.port.trim()) ?? 4455} tcp:${int.tryParse(state.port.trim()) ?? 4455}';

    _syncControllerText(_hostController, state.host);
    _syncControllerText(_portController, state.port);
    _syncControllerText(_passwordController, state.password);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/controller'),
        title: const BrandAppBarTitle(title: 'DeckPilot for OBS'),
        actions: <Widget>[
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
                  _ConnectionMethodSelector(
                    selected: state.connectionMethod,
                    onSelected: controller.updateConnectionMethod,
                  ),
                  const SizedBox(height: 12),
                  ObsConnectionCard(
                    status: state.status,
                    message: state.statusMessage,
                  ),
                  if (isUsbMode) ...<Widget>[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'USB Mode (No Wi-Fi)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Use USB Mode if Wi-Fi is unavailable.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
                                  onPressed: state.isBusy
                                      ? null
                                      : controller.applyUsbDefaults,
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
                                          duration:
                                              Duration(milliseconds: 1200),
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
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: state.isBusy || state.isDetecting || isUsbMode
                        ? null
                        : controller.autoDetect,
                    icon: state.isDetecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: const Text('Find OBS Automatically'),
                  ),
                  if (state.isDetecting) ...<Widget>[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 6),
                    Text(
                      'Scanning your local network for OBS WebSocket servers...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (state.discoveredDevices.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _DiscoveredDeviceSection(
                      devices: state.discoveredDevices,
                      isBusy: state.isBusy,
                      onUseDevice: (device) async {
                        if (device.requiresPassword &&
                            state.password.trim().isEmpty) {
                          setState(() => _manualExpanded = true);
                        }
                        await controller.useDiscoveredDevice(device);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (_canScanQr)
                    OutlinedButton.icon(
                      onPressed: state.isBusy || state.isDetecting
                          ? null
                          : () => _scanQrCode(controller),
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      label: const Text('Scan QR Code'),
                    ),
                  if (state.savedConnections.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    _SavedConnectionsSection(
                      connections: state.savedConnections,
                      busy: state.isBusy,
                      onConnect: controller.connectToSaved,
                      onDelete: controller.removeSavedConnection,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: _manualExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() => _manualExpanded = expanded);
                      },
                      leading: const Icon(Icons.tune),
                      title: const Text('Manual Setup'),
                      subtitle: Text(
                        isUsbMode
                            ? 'USB host/port/password'
                            : 'Host, port, and password',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      children: <Widget>[
                        TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(
                            labelText: 'Host Address',
                            hintText: '192.168.1.10',
                            prefixIcon: Icon(Icons.dns_outlined),
                            helperText:
                                'Use the IP address of the computer running OBS.',
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
                                onPressed:
                                    state.isBusy ? null : controller.connect,
                                icon: state.isBusy
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
                                onPressed: state.isBusy
                                    ? null
                                    : controller.testConnection,
                                icon: const Icon(Icons.network_check),
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
                                onPressed:
                                    state.isBusy ? null : controller.disconnect,
                                icon: const Icon(Icons.link_off),
                                label: const Text('Disconnect'),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: state.isBusy
                                    ? null
                                    : controller.clearSavedConnection,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Clear Saved'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: <Widget>[
                        SwitchListTile.adaptive(
                          value: state.autoReconnect,
                          title: const Text('Auto reconnect'),
                          subtitle: const Text(
                              'Retry automatically if OBS disconnects.'),
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
                'Scan QR JSON: {"host":"192.168.1.10","port":4455,"password":"..."}',
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
