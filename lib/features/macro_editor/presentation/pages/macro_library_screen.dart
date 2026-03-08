import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/macro_definition.dart';
import '../../../../domain/entities/obs_action_catalog.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/brand_identity.dart';
import '../controllers/macro_library_controller.dart';

class MacroLibraryScreen extends ConsumerWidget {
  const MacroLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(macroLibraryControllerProvider);
    final controller = ref.read(macroLibraryControllerProvider.notifier);
    final volunteerMode = ref.watch(volunteerModeProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/controller'),
        title: const BrandAppBarTitle(title: 'Macros'),
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
            : state.macros.isEmpty
                ? _EmptyMacrosState(
                    onCreate: volunteerMode
                        ? null
                        : () => context.push('/macro-editor'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                    itemCount: state.macros.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final macro = state.macros[index];
                      final running = state.runningMacroIds.contains(macro.id);
                      return _MacroCard(
                        macro: macro,
                        running: running,
                        volunteerMode: volunteerMode,
                        isSystemMacro: controller.isSystemMacro(macro.id),
                        onEdit: volunteerMode
                            ? null
                            : () async {
                                await context
                                    .push('/macro-editor?macroId=${macro.id}');
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
                                        backgroundColor:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                    );
                                }
                              },
                        onAssign: volunteerMode
                            ? null
                            : () async {
                                final assignment = await showModalBottomSheet<
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
                                        backgroundColor:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                    );
                                }
                              },
                        onDuplicate: volunteerMode
                            ? null
                            : () async {
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
                        onDelete: volunteerMode
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
                                        backgroundColor:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                    );
                                }
                              },
                      );
                    },
                  ),
      ),
      floatingActionButton: volunteerMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/macro-editor'),
              icon: const Icon(Icons.add),
              label: const Text('Create Macro'),
            ),
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
    required this.onEdit,
    required this.onTest,
    required this.onAssign,
    required this.onDuplicate,
    required this.onDelete,
  });

  final MacroDefinition macro;
  final bool running;
  final bool volunteerMode;
  final bool isSystemMacro;
  final VoidCallback? onEdit;
  final VoidCallback? onTest;
  final VoidCallback? onAssign;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(isSystemMacro ? 'Protected' : 'Delete'),
                ),
              ],
            ),
            if (volunteerMode) ...<Widget>[
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
