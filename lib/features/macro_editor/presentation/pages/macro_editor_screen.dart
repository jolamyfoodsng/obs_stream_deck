import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/macro_definition.dart';
import '../../../../domain/entities/obs_action_catalog.dart';
import '../../../../domain/entities/premium_feature.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/premium_upgrade_modal.dart';
import '../controllers/macro_editor_controller.dart';

class MacroEditorScreen extends ConsumerStatefulWidget {
  const MacroEditorScreen({super.key, this.macroId});

  final String? macroId;

  @override
  ConsumerState<MacroEditorScreen> createState() => _MacroEditorScreenState();
}

class _MacroEditorScreenState extends ConsumerState<MacroEditorScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(macroEditorControllerProvider(widget.macroId));
    _nameController = TextEditingController(text: state.macro.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumControllerProvider);
    final state = ref.watch(macroEditorControllerProvider(widget.macroId));
    final controller =
        ref.read(macroEditorControllerProvider(widget.macroId).notifier);
    final lockedForPlan = controller.isLockedForCurrentPlan;

    if (_nameController.text != state.macro.name) {
      _nameController.value = _nameController.value.copyWith(
        text: state.macro.name,
        selection: TextSelection.collapsed(offset: state.macro.name.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Macro Editor'),
            Text(
              'Editing: ${state.macro.name}'.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(
                  onPressed: lockedForPlan ? null : controller.testMacro,
                  child: const Text('Test'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: state.isSaving || lockedForPlan
                      ? null
                      : () async {
                          final saved = await controller.save();
                          if (!context.mounted) return;
                          switch (saved) {
                            case MacroSaveResult.success:
                              _closeEditor(context);
                              break;
                            case MacroSaveResult.blockedByPremium:
                              await showPremiumUpgradeModal(
                                context,
                                highlightedFeature: PremiumFeature.macros,
                              );
                              break;
                            case MacroSaveResult.validationFailed:
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Enter a macro name first.'),
                                  ),
                                );
                              break;
                            case MacroSaveResult.failed:
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not save macro.'),
                                  ),
                                );
                              break;
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (!premium.isPremium) ...<Widget>[
                  _FreeMacroEditorBanner(
                    lockedForPlan: lockedForPlan,
                    onUpgrade: () {
                      showPremiumUpgradeModal(
                        context,
                        highlightedFeature: PremiumFeature.macros,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                _Section(
                  children: <Widget>[
                    Text(
                      'Macro Metadata',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      enabled: !lockedForPlan,
                      decoration: const InputDecoration(
                        labelText: 'Macro Name',
                        hintText: 'Enter macro name...',
                      ),
                      onChanged: controller.updateName,
                    ),
                    const SizedBox(height: 10),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _MetaChip(
                            icon: Icons.label_outline, label: 'Streaming'),
                        _MetaChip(icon: Icons.schedule, label: 'Auto-Run'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'Action Stack',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: lockedForPlan
                              ? null
                              : () => _pickAndAddStep(controller),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Add Action'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: state.macro.steps.length,
                      onReorder:
                          lockedForPlan ? (_, __) {} : controller.reorderSteps,
                      itemBuilder: (context, index) {
                        final step = state.macro.steps[index];
                        return _MacroStepRow(
                          key: ValueKey<String>(step.id),
                          step: step,
                          index: index,
                          onTap: lockedForPlan
                              ? null
                              : () => _editStep(controller, step),
                          onDelete: lockedForPlan
                              ? null
                              : () => controller.removeStep(step.id),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.9),
                        ),
                      ),
                      onPressed:
                          lockedForPlan ? null : () => _pickAndAddStep(controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Insert New Step'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.macros,
      ),
    );
  }

  Future<void> _pickAndAddStep(MacroEditorController controller) async {
    final selected = await showModalBottomSheet<MacroActionType>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: controller.availableActionTypes().map((type) {
              return ListTile(
                leading: Icon(_stepIcon(type), color: _stepColor(type)),
                title: Text(controller.labelForActionType(type)),
                onTap: () => Navigator.of(sheetContext).pop(type),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selected != null) {
      final result = controller.addStep(selected);
      if (result == MacroStepAddResult.blockedByPremium && mounted) {
        await showPremiumUpgradeModal(
          context,
          highlightedFeature: PremiumFeature.macros,
        );
      }
    }
  }

  Future<void> _editStep(
    MacroEditorController controller,
    MacroAction step,
  ) async {
    final definition = controller.actionDefinition(step.type);
    if (definition.targetKind == ObsActionTargetKind.delayMs) {
      final delayController = TextEditingController(
        text: '${step.delayMs ?? 1000}',
      );
      final nextDelay = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Delay (ms)'),
            content: TextField(
              controller: delayController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '1000',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = int.tryParse(delayController.text.trim());
                  Navigator.of(dialogContext).pop(parsed);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      delayController.dispose();

      if (nextDelay != null) {
        controller.updateStepDelay(stepId: step.id, delayMs: nextDelay);
      }
      return;
    }

    if (!definition.requiresTarget) {
      return;
    }

    final targets = controller.availableTargets(step.type);
    if (targets.isEmpty) return;

    final selectedTarget = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: targets.map((target) {
              final isSelected = target.id == step.targetId;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(target.label),
                onTap: () => Navigator.of(sheetContext).pop(target.id),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selectedTarget != null) {
      controller.updateStepTarget(stepId: step.id, targetId: selectedTarget);
    }
  }

  void _closeEditor(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
    } else {
      context.go('/macros');
    }
  }
}

class _FreeMacroEditorBanner extends StatelessWidget {
  const _FreeMacroEditorBanner({
    required this.lockedForPlan,
    required this.onUpgrade,
  });

  final bool lockedForPlan;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.8),
        ),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            lockedForPlan ? 'Macro limit reached' : 'Free macro builder',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            lockedForPlan
                ? 'Free includes ${AppConstants.freeMacroLimit} macro with up to ${AppConstants.freeMacroActionLimit} actions. Upgrade to edit more advanced automation.'
                : 'You can build ${AppConstants.freeMacroLimit} macro with up to ${AppConstants.freeMacroActionLimit} actions before upgrading.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (lockedForPlan) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Unlock Premium Macros'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.7),
        ),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _MacroStepRow extends StatelessWidget {
  const _MacroStepRow({
    super.key,
    required this.step,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  final MacroAction step;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _stepColor(step.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.7),
            ),
            color:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_stepIcon(step.type), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          '${index + 1}'.padLeft(2, '0'),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _stepTitle(step.type),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stepSubtitle(step),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                tooltip: 'Delete step',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _stepTitle(MacroActionType type) {
  return ObsActionCatalog.definitionForMacroType(type).label;
}

String _stepSubtitle(MacroAction step) {
  if (step.type == MacroActionType.delay) {
    final ms = step.delayMs ?? 0;
    return 'Wait for ${(ms / 1000).toStringAsFixed(1)} seconds';
  }

  final target = step.targetName ?? step.targetId;
  if (target == null || target.isEmpty) {
    return 'No target selected';
  }

  return 'Target: $target';
}

IconData _stepIcon(MacroActionType type) {
  final code = ObsActionCatalog.codeForMacroType(type);
  switch (code) {
    case ObsActionCode.switchScene:
      return Icons.tv;
    case ObsActionCode.setPreviewScene:
      return Icons.preview;
    case ObsActionCode.showSource:
      return Icons.visibility;
    case ObsActionCode.hideSource:
      return Icons.visibility_off;
    case ObsActionCode.toggleSourceVisibility:
      return Icons.layers;
    case ObsActionCode.mute:
      return Icons.volume_off;
    case ObsActionCode.unmute:
      return Icons.volume_up;
    case ObsActionCode.toggleMute:
      return Icons.mic;
    case ObsActionCode.startStream:
      return Icons.podcasts;
    case ObsActionCode.stopStream:
      return Icons.stop_circle_outlined;
    case ObsActionCode.toggleStream:
      return Icons.sync;
    case ObsActionCode.startRecording:
      return Icons.radio_button_checked;
    case ObsActionCode.stopRecording:
      return Icons.stop;
    case ObsActionCode.pauseRecording:
      return Icons.pause_circle_outline;
    case ObsActionCode.resumeRecording:
      return Icons.play_circle_outline;
    case ObsActionCode.toggleRecording:
      return Icons.sync_alt;
    case ObsActionCode.startVirtualCamera:
      return Icons.videocam;
    case ObsActionCode.stopVirtualCamera:
      return Icons.videocam_off;
    case ObsActionCode.toggleVirtualCamera:
      return Icons.cameraswitch;
    case ObsActionCode.enableStudioMode:
      return Icons.slideshow;
    case ObsActionCode.disableStudioMode:
      return Icons.slideshow_outlined;
    case ObsActionCode.toggleStudioMode:
      return Icons.tune;
    case ObsActionCode.runMacro:
      return Icons.bolt;
    case ObsActionCode.delay:
      return Icons.timer;
  }
}

Color _stepColor(MacroActionType type) {
  final code = ObsActionCatalog.codeForMacroType(type);
  switch (code) {
    case ObsActionCode.switchScene:
      return const Color(0xFF137FEC);
    case ObsActionCode.setPreviewScene:
      return const Color(0xFF1D4ED8);
    case ObsActionCode.showSource:
      return const Color(0xFF10B981);
    case ObsActionCode.hideSource:
      return const Color(0xFFF97316);
    case ObsActionCode.toggleSourceVisibility:
      return const Color(0xFF8B5CF6);
    case ObsActionCode.mute:
      return const Color(0xFF2563EB);
    case ObsActionCode.unmute:
      return const Color(0xFF0EA5E9);
    case ObsActionCode.toggleMute:
      return const Color(0xFF3B82F6);
    case ObsActionCode.startStream:
      return const Color(0xFF22C55E);
    case ObsActionCode.stopStream:
      return const Color(0xFFEF4444);
    case ObsActionCode.toggleStream:
      return const Color(0xFF16A34A);
    case ObsActionCode.startRecording:
      return const Color(0xFFDC2626);
    case ObsActionCode.stopRecording:
      return const Color(0xFFB91C1C);
    case ObsActionCode.pauseRecording:
      return const Color(0xFFF59E0B);
    case ObsActionCode.resumeRecording:
      return const Color(0xFF059669);
    case ObsActionCode.toggleRecording:
      return const Color(0xFFCA8A04);
    case ObsActionCode.startVirtualCamera:
      return const Color(0xFF0891B2);
    case ObsActionCode.stopVirtualCamera:
      return const Color(0xFFB91C1C);
    case ObsActionCode.toggleVirtualCamera:
      return const Color(0xFF0E7490);
    case ObsActionCode.enableStudioMode:
      return const Color(0xFF1D4ED8);
    case ObsActionCode.disableStudioMode:
      return const Color(0xFF7C3AED);
    case ObsActionCode.toggleStudioMode:
      return const Color(0xFF2563EB);
    case ObsActionCode.runMacro:
      return const Color(0xFF7C3AED);
    case ObsActionCode.delay:
      return const Color(0xFFF59E0B);
  }
}
