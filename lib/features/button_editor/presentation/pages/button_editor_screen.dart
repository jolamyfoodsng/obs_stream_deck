import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/button_action.dart';
import '../../../../shared/extensions/color_extensions.dart';
import '../../../../shared/extensions/icon_mapper.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/app_section_header.dart';
import '../../../../shared/widgets/deck_button.dart';
import '../controllers/button_editor_controller.dart';

class ButtonEditorScreen extends ConsumerStatefulWidget {
  const ButtonEditorScreen({
    super.key,
    this.buttonId,
    this.pageId,
    this.slotPosition,
  });

  final String? buttonId;
  final String? pageId;
  final int? slotPosition;

  @override
  ConsumerState<ButtonEditorScreen> createState() => _ButtonEditorScreenState();
}

class _ButtonEditorScreenState extends ConsumerState<ButtonEditorScreen> {
  late final TextEditingController _labelController;
  late final ButtonEditorArgs _args;

  @override
  void initState() {
    super.initState();
    _args = ButtonEditorArgs(
      buttonId: widget.buttonId,
      pageId: widget.pageId,
      slotPosition: widget.slotPosition,
    );
    final state = ref.read(buttonEditorControllerProvider(_args));
    _labelController = TextEditingController(text: state.button.label);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final volunteerMode = ref.watch(volunteerModeProvider);

    if (volunteerMode) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/controller'),
          title: const Text('Edit Button'),
        ),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Volunteer Mode is active. Button editing is disabled.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final state = ref.watch(buttonEditorControllerProvider(_args));
    final controller = ref.read(buttonEditorControllerProvider(_args).notifier);
    final premium = ref.watch(premiumControllerProvider);
    const colorOptions = <String>[
      '#137FEC',
      '#F59E0B',
      '#8B5CF6',
      '#EF4444',
      '#64748B',
      '#14B8A6',
    ];

    if (_labelController.text != state.button.label) {
      _labelController.value = _labelController.value.copyWith(
        text: state.button.label,
        selection: TextSelection.collapsed(offset: state.button.label.length),
      );
    }

    final actionType = state.button.action.type;
    final actionDefinition = controller.actionDefinition(actionType);
    final actionTypes = controller.availableActionTypes();
    final targets = controller.availableTargets(actionType);
    final selectedTargetId = state.button.action.targetId;
    final selectedTargetValue = selectedTargetId != null &&
            targets.any((item) => item.id == selectedTargetId)
        ? selectedTargetId
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Edit Button'),
        actions: <Widget>[
          TextButton(
            onPressed: state.isSaving
                ? null
                : () async {
                    final saved = await controller.save();
                    if (saved && context.mounted) {
                      _closeEditor(context);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const AppSectionHeader(
              title: 'Preview',
              subtitle: 'Live button preview with current properties.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Card(
                child: Center(
                  child: SizedBox(
                    width: 120,
                    child: DeckButton(
                      button: state.button,
                      active: true,
                      enabled: true,
                      showHoldBadge: true,
                      onTap: () {},
                      onLongPress: () {},
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'Configuration'),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(labelText: 'Button Label'),
              onChanged: controller.updateLabel,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ButtonActionType>(
              key: ValueKey<String>(
                  'action-type-${state.button.action.type.name}'),
              initialValue: state.button.action.type,
              decoration: const InputDecoration(labelText: 'Action Type'),
              items: actionTypes
                  .map(
                    (type) => DropdownMenuItem<ButtonActionType>(
                      value: type,
                      child: Text(controller.labelForActionType(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                controller.updateActionType(value);
              },
            ),
            const SizedBox(height: 14),
            if (actionDefinition.requiresTarget)
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  'action-target-${state.button.action.targetId ?? ''}-${targets.length}',
                ),
                initialValue: selectedTargetValue,
                decoration: InputDecoration(
                  labelText: controller.targetFieldLabel(actionType),
                  helperText: actionDefinition.requiresStudioMode &&
                          !state.obsState.studioModeEnabled
                      ? 'Studio Mode is currently disabled in OBS.'
                      : null,
                ),
                items: targets
                    .map(
                      (target) => DropdownMenuItem<String>(
                        value: target.id,
                        child: Text(target.label),
                      ),
                    )
                    .toList(),
                onChanged: targets.isEmpty
                    ? null
                    : controller.updateActionTarget,
              ),
            if (actionDefinition.requiresTarget && targets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  actionType == ButtonActionType.runMacro
                      ? premium.isPremium
                          ? 'No macros available yet. Create one in the Macros tab.'
                          : 'No free macros available yet. Create one in the Macros tab. Free includes ${AppConstants.freeMacroLimit} macro with up to ${AppConstants.freeMacroActionLimit} actions.'
                      : 'No targets available for this action yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (actionType == ButtonActionType.runMacro) ...<Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  premium.isPremium
                      ? 'Assign any saved macro to this button.'
                      : 'Macro buttons work on the free plan too. Free includes ${AppConstants.freeMacroLimit} macro with up to ${AppConstants.freeMacroActionLimit} actions.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Active Color',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colorOptions
                  .map(
                    (hex) => _ColorChip(
                      hex: hex,
                      selected: state.button.activeColor == hex,
                      onTap: () => controller.updateActiveColor(hex),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text(
              'Inactive Color',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colorOptions
                  .map(
                    (hex) => _ColorChip(
                      hex: hex,
                      selected: state.button.inactiveColor == hex,
                      onTap: () => controller.updateInactiveColor(hex),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Card(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              child: SwitchListTile.adaptive(
                value: state.button.longPressTrigger,
                title: const Text('Long-press Trigger'),
                subtitle: const Text('Action only fires when button is held.'),
                secondary: const Icon(Icons.touch_app_outlined),
                onChanged: controller.updateLongPressTrigger,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 120,
              child: GridView.count(
                crossAxisCount: 6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: controller.availableIcons().take(18).map((icon) {
                  final selected = icon == state.button.icon;
                  return InkWell(
                    onTap: () => controller.updateIcon(icon),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.18)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Icon(IconMapper.fromName(icon)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.testAction,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Test Action'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () async {
                            final saved = await controller.save();
                            if (saved && context.mounted) {
                              _closeEditor(context);
                            }
                          },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.control,
      ),
    );
  }

  void _closeEditor(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
    } else {
      context.go('/controller');
    }
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hex.toColor(),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}
