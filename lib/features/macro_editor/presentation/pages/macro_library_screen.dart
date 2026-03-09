import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/macro_plan_access.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/macro_definition.dart';
import '../../../../domain/entities/obs_action_catalog.dart';
import '../../../../domain/entities/premium_feature.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../../../../shared/widgets/page_helper_text.dart';
import '../../../../shared/widgets/premium_upgrade_modal.dart';
import '../../../../shared/widgets/pro_badge.dart';
import '../controllers/macro_library_controller.dart';

class MacroLibraryScreen extends ConsumerWidget {
  const MacroLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(macroLibraryControllerProvider);
    final controller = ref.read(macroLibraryControllerProvider.notifier);
    final volunteerMode = ref.watch(volunteerModeProvider);
    final premium = ref.watch(premiumControllerProvider);
    final accessibleMacros = MacroPlanAccess.accessibleMacros(
      isPremium: premium.isPremium,
      macros: state.macros,
    );
    final lockedMacros = premium.isPremium
        ? const <MacroDefinition>[]
        : state.macros
            .where(
              (macro) => MacroPlanAccess.isLockedForFreePlan(
                isPremium: premium.isPremium,
                macros: state.macros,
                macro: macro,
              ),
            )
            .toList(growable: false);
    final canCreateMacro = MacroPlanAccess.canCreateMacro(
      isPremium: premium.isPremium,
      macros: state.macros,
    );
    final hasAccessibleMacros = accessibleMacros.isNotEmpty;
    final showCreateFab = !volunteerMode && hasAccessibleMacros;

    Future<void> openUpgrade([PremiumFeature feature = PremiumFeature.macros]) {
      return showPremiumUpgradeModal(
        context,
        highlightedFeature: feature,
      );
    }

    Future<void> handleCreateMacro() async {
      if (volunteerMode) return;
      if (!canCreateMacro) {
        await openUpgrade();
        return;
      }
      if (!context.mounted) return;
      await context.push('/macro-editor');
    }

    Future<void> previewLockedMacro(MacroDefinition macro) async {
      final shouldUpgrade = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LockedMacroPreviewSheet(macro: macro),
      );
      if (shouldUpgrade == true && context.mounted) {
        await openUpgrade();
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/controller'),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandAppBarTitle(title: 'Macros'),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => controller.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                children: <Widget>[
                  const PageHelperText(
                    text:
                        'Create automation buttons that perform multiple OBS actions.',
                    padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
                  ),
                  if (accessibleMacros.isEmpty)
                    _EmptyMacrosState(
                      onCreate: volunteerMode
                          ? null
                          : () {
                              handleCreateMacro();
                            },
                    )
                  else
                    ...accessibleMacros.map(
                      (macro) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MacroCard(
                          macro: macro,
                          running: state.runningMacroIds.contains(macro.id),
                          volunteerMode: volunteerMode,
                          isSystemMacro: controller.isSystemMacro(macro.id),
                          locked: false,
                          onEdit: volunteerMode
                              ? null
                              : () async {
                                  await context.push(
                                      '/macro-editor?macroId=${macro.id}');
                                  if (context.mounted) {
                                    await controller.refresh();
                                  }
                                },
                          onTest: volunteerMode
                              ? null
                              : () async {
                                  try {
                                    await controller.testMacro(macro.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Macro "${macro.name}" executed.',
                                          ),
                                          duration:
                                              const Duration(milliseconds: 1400),
                                        ),
                                      );
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text('Macro failed: $error'),
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      );
                                  }
                                },
                          onAssign: volunteerMode
                              ? null
                              : () async {
                                  final assignment =
                                      await showModalBottomSheet<
                                          _AssignMacroResult>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => _AssignMacroSheet(
                                      macro: macro,
                                      pages: state.pages,
                                      controller: controller,
                                    ),
                                  );

                                  if (assignment == null) return;
                                  try {
                                    await controller.assignMacroToSlot(
                                      macro: macro,
                                      pageId: assignment.pageId,
                                      slotIndex: assignment.slotIndex,
                                      customLabel: assignment.label,
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Assigned "${macro.name}" to ${assignment.pageName} slot ${assignment.slotIndex + 1}.',
                                          ),
                                          duration:
                                              const Duration(milliseconds: 1700),
                                        ),
                                      );
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text('Assign failed: $error'),
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      );
                                  }
                                },
                          onDuplicate: volunteerMode
                              ? null
                              : () async {
                                  if (!premium.isPremium && !canCreateMacro) {
                                    await openUpgrade();
                                    return;
                                  }
                                  await controller.duplicateMacro(macro.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('Duplicated "${macro.name}".'),
                                        duration:
                                            const Duration(milliseconds: 1200),
                                      ),
                                    );
                                },
                          onDelete: volunteerMode || controller.isSystemMacro(macro.id)
                              ? null
                              : () async {
                                  final shouldDelete = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) {
                                      return AlertDialog(
                                        title: const Text('Delete Macro?'),
                                        content: Text(
                                          'Delete "${macro.name}"? This cannot be undone.',
                                        ),
                                        actions: <Widget>[
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(dialogContext)
                                                    .pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(dialogContext)
                                                    .pop(true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                              foregroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .onError,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      );
                                    },
                                  );

                                  if (shouldDelete != true) return;
                                  try {
                                    await controller.deleteMacro(macro.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Deleted "${macro.name}".'),
                                          duration:
                                              const Duration(milliseconds: 1200),
                                        ),
                                      );
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text('$error'),
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      );
                                  }
                                },
                        ),
                      ),
                    ),
                  if (lockedMacros.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          'Premium Automation',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        const ProBadge(compact: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'See advanced macro workflows first. Upgrade only when you want more than ${AppConstants.freeMacroLimit} macro or ${AppConstants.freeMacroActionLimit} steps.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 10),
                    ...lockedMacros.map(
                      (macro) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MacroCard(
                          macro: macro,
                          running: false,
                          volunteerMode: volunteerMode,
                          isSystemMacro: controller.isSystemMacro(macro.id),
                          locked: true,
                          onUpgrade: () {
                            previewLockedMacro(macro);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
      floatingActionButton: showCreateFab
          ? FloatingActionButton.extended(
              onPressed: () {
                handleCreateMacro();
              },
              icon: Icon(
                premium.isPremium || canCreateMacro
                    ? Icons.add
                    : Icons.lock_outline,
              ),
              label: const Text('Create Macro'),
            )
          : null,
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.macros,
      ),
    );
  }
}

class _MacroCard extends StatelessWidget {
  const _MacroCard({
    required this.macro,
    required this.running,
    required this.volunteerMode,
    required this.isSystemMacro,
    required this.locked,
    this.onEdit,
    this.onTest,
    this.onAssign,
    this.onDuplicate,
    this.onDelete,
    this.onUpgrade,
  });

  final MacroDefinition macro;
  final bool running;
  final bool volunteerMode;
  final bool isSystemMacro;
  final bool locked;
  final VoidCallback? onEdit;
  final VoidCallback? onTest;
  final VoidCallback? onAssign;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.72 : 1,
      child: Card(
        child: InkWell(
          onTap: locked ? onUpgrade : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const BrandSymbol(size: 20, useSmallAsset: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        macro.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (locked) ...<Widget>[
                      const ProBadge(compact: true),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${macro.steps.length} steps',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _macroSummary(macro),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (locked) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Available in Premium. Free users can build one macro with up to three actions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: locked
                      ? <Widget>[
                          FilledButton.tonalIcon(
                            onPressed: onUpgrade,
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Preview'),
                          ),
                        ]
                      : <Widget>[
                          OutlinedButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: running ? null : onTest,
                            icon: running
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: const Text('Test'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onAssign,
                            icon: const Icon(Icons.grid_view),
                            label: const Text('Assign'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onDuplicate,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Duplicate'),
                          ),
                          if (!isSystemMacro)
                            OutlinedButton.icon(
                              onPressed: onDelete,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                            ),
                        ],
                ),
                if (volunteerMode && !locked) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Volunteer Mode: macro management actions are disabled.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _macroSummary(MacroDefinition macro) {
    if (macro.steps.isEmpty) {
      return 'No steps yet. Add actions to make this macro useful.';
    }

    final mapped = macro.steps
        .take(3)
        .map((step) => ObsActionCatalog.definitionForMacroType(step.type).label)
        .toList(growable: false);

    final summary = mapped.join('  ->  ');
    if (macro.steps.length <= 3) return summary;
    return '$summary  +${macro.steps.length - 3} more';
  }
}

class _LockedMacroPreviewSheet extends StatelessWidget {
  const _LockedMacroPreviewSheet({required this.macro});

  final MacroDefinition macro;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const BrandSymbol(size: 22, useSmallAsset: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      macro.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const ProBadge(compact: true),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'This premium macro is ready to run multiple OBS actions in order. Free users can inspect it first, then upgrade only if they want to use more powerful automation.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              Text(
                '${macro.steps.length} steps',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ...macro.steps.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LockedMacroStepRow(
                        index: entry.key,
                        step: entry.value,
                      ),
                    ),
                  ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Maybe Later'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Upgrade'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedMacroStepRow extends StatelessWidget {
  const _LockedMacroStepRow({
    required this.index,
    required this.step,
  });

  final int index;
  final MacroAction step;

  @override
  Widget build(BuildContext context) {
    final label = ObsActionCatalog.definitionForMacroType(step.type).label;
    final subtitle = _stepSubtitle(step);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.7),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _stepSubtitle(MacroAction step) {
    if (step.type == MacroActionType.delay) {
      final delayMs = step.delayMs ?? 0;
      final seconds = delayMs / 1000;
      return 'Wait for ${seconds.toStringAsFixed(seconds.truncateToDouble() == seconds ? 0 : 1)} seconds';
    }

    if ((step.targetName ?? '').trim().isNotEmpty) {
      return step.targetName;
    }

    if ((step.targetId ?? '').trim().isNotEmpty) {
      return step.targetId;
    }

    return null;
  }
}

class _EmptyMacrosState extends StatelessWidget {
  const _EmptyMacrosState({this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandSymbol(size: 56),
            const SizedBox(height: 10),
            Text(
              'No macros yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create macros to run multiple OBS actions in sequence.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (onCreate != null) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create Macro'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssignMacroResult {
  const _AssignMacroResult({
    required this.pageId,
    required this.pageName,
    required this.slotIndex,
    required this.label,
  });

  final String pageId;
  final String pageName;
  final int slotIndex;
  final String label;
}

class _AssignMacroSheet extends StatefulWidget {
  const _AssignMacroSheet({
    required this.macro,
    required this.pages,
    required this.controller,
  });

  final MacroDefinition macro;
  final List<ControllerPage> pages;
  final MacroLibraryController controller;

  @override
  State<_AssignMacroSheet> createState() => _AssignMacroSheetState();
}

class _AssignMacroSheetState extends State<_AssignMacroSheet> {
  late String _selectedPageId;
  int _selectedSlot = 0;
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    final firstPage = widget.pages.firstOrNull;
    _selectedPageId = firstPage?.id ?? '';
    _labelController = TextEditingController(text: widget.macro.name);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final selectedPage =
        widget.pages.where((page) => page.id == _selectedPageId).firstOrNull;
    final maxSlots = selectedPage == null
        ? 0
        : widget.controller.maxAssignableSlotsForPage(selectedPage);
    final slots = List<int>.generate(maxSlots, (index) => index);

    if (_selectedSlot >= maxSlots && maxSlots > 0) {
      _selectedSlot = 0;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Assign Macro',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.macro.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      _selectedPageId.isEmpty ? null : _selectedPageId,
                  decoration: const InputDecoration(labelText: 'Target Page'),
                  items: widget.pages
                      .map(
                        (page) => DropdownMenuItem<String>(
                          value: page.id,
                          child: Text(page.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedPageId = value;
                      _selectedSlot = 0;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue:
                      slots.contains(_selectedSlot) ? _selectedSlot : null,
                  decoration: const InputDecoration(labelText: 'Slot Position'),
                  items: slots
                      .map(
                        (slot) => DropdownMenuItem<int>(
                          value: slot,
                          child: Text('Slot ${slot + 1}'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: slots.isEmpty
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _selectedSlot = value);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Button Label',
                    hintText: 'Use macro name',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: selectedPage == null
                            ? null
                            : () {
                                Navigator.of(context).pop(
                                  _AssignMacroResult(
                                    pageId: selectedPage.id,
                                    pageName: selectedPage.name,
                                    slotIndex: _selectedSlot,
                                    label: _labelController.text.trim(),
                                  ),
                                );
                              },
                        child: const Text('Assign'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
