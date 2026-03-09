import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/premium_feature.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/page_helper_text.dart';
import '../../../../shared/widgets/premium_upgrade_modal.dart';
import '../../../../shared/widgets/pro_badge.dart';
import '../controllers/page_manager_controller.dart';

class PageManagerScreen extends ConsumerStatefulWidget {
  const PageManagerScreen({super.key});

  @override
  ConsumerState<PageManagerScreen> createState() => _PageManagerScreenState();
}

class _PageManagerScreenState extends ConsumerState<PageManagerScreen> {
  Future<void> _showPagePremiumPreview({
    required PremiumFeature feature,
    required String title,
    required String description,
    required List<String> bullets,
  }) async {
    final shouldUpgrade = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PagePremiumPreviewSheet(
        title: title,
        description: description,
        bullets: bullets,
      ),
    );

    if (shouldUpgrade == true && mounted) {
      await showPremiumUpgradeModal(
        context,
        highlightedFeature: feature,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pageManagerControllerProvider);
    final controller = ref.read(pageManagerControllerProvider.notifier);
    final volunteerMode = ref.watch(volunteerModeProvider);
    final premium = ref.watch(premiumControllerProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Pages'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFF137FEC)),
            tooltip: 'Done',
            onPressed: () => context.go('/controller'),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const PageHelperText(
                      text:
                          'Organize your control pages. Each page can contain buttons for scenes, audio, or macros.',
                      padding: EdgeInsets.fromLTRB(0, 0, 0, 10),
                    ),
                    Text(
                      'MANAGE LAYOUT',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Drag and drop rows to reorder your OBS controller pages.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (volunteerMode) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        'Volunteer Mode is active. Page editing is disabled.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: state.pages.length,
                        onReorder:
                            volunteerMode ? (_, __) {} : controller.reorder,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          final page = state.pages[index];
                          final premiumLockedPage =
                              !premium.isPremium && _isPremiumOnlyPage(page);
                          return Opacity(
                            key: ValueKey<String>(page.id),
                            opacity: premiumLockedPage ? 0.72 : 1,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.8),
                                ),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface
                                    .withValues(alpha: 0.75),
                              ),
                              child: Row(
                                children: <Widget>[
                                  if (!volunteerMode)
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_indicator,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.lock_outline,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  const SizedBox(width: 12),
                                  _LayoutPreview(page: page),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(
                                                'Page ${index + 1}: ${page.name}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            if (premiumLockedPage) ...<Widget>[
                                              const SizedBox(width: 8),
                                              const ProBadge(compact: true),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${page.buttonCount} widgets active',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!volunteerMode)
                                    IconButton(
                                      onPressed: () async {
                                        if (premiumLockedPage) {
                                          await _showPagePremiumPreview(
                                            feature: PremiumFeature.emergencyPage,
                                            title: 'Emergency Page Preview',
                                            description:
                                                'Keep your critical fallback controls one tap away during a live issue.',
                                            bullets: const <String>[
                                              'Safe Scene and BRB switching',
                                              'Mute All, Hide Camera, Hide Overlays',
                                              'Protected stop/restart stream controls',
                                            ],
                                          );
                                          return;
                                        }
                                        await _showPageActions(
                                          context: context,
                                          controller: controller,
                                          page: page,
                                        );
                                      },
                                      icon: Icon(
                                        Icons.edit,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      tooltip: 'Edit page actions',
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (!premium.isPremium) ...<Widget>[
                      const SizedBox(height: 10),
                      ...List<Widget>.generate(
                        AppConstants.freeLockedPagePreviewCount,
                        (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _LockedPagePreviewCard(
                            pageNumber: state.pages.length + index + 1,
                            onTap: () => _showPagePremiumPreview(
                              feature: PremiumFeature.unlimitedPages,
                              title: 'More Deck Pages',
                              description:
                                  'Create separate layouts for scenes, media, audio, emergency actions, and volunteer operators.',
                              bullets: const <String>[
                                'Unlimited deck pages',
                                'Dedicated layouts for different workflows',
                                'Fast switching between custom pages',
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!volunteerMode) ...<Widget>[
                      const SizedBox(height: 8),
                      _AddNewPageButton(
                        onTap: () => _openCreatePageSheet(controller),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      bottomNavigationBar: const AppBottomNav(
        currentTab: AppBottomNavTab.pages,
      ),
    );
  }

  Future<void> _showPageActions({
    required BuildContext context,
    required PageManagerController controller,
    required ControllerPage page,
  }) async {
    if (ref.read(volunteerModeProvider)) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Layout'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/controller');
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final name = await _showRenameDialog(context, page.name);
                  if (name != null && name.trim().isNotEmpty) {
                    await controller.renamePage(page.id, name.trim());
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Duplicate'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final duplicated = await controller.duplicatePage(page.id);
                  if (!context.mounted) return;
                  if (!duplicated) {
                    await _showPageLimitReachedDialog();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.grade_outlined),
                title: Text(page.isDefault ? 'Unset Default' : 'Set Default'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await controller.setDefault(page.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                iconColor: Theme.of(context).colorScheme.error,
                textColor: Theme.of(context).colorScheme.error,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ok = await _confirmDeletePageDialog(context, page);
                  if (ok) {
                    await controller.deletePage(page.id);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCreatePageSheet(PageManagerController controller) async {
    if (ref.read(volunteerModeProvider)) return;

    final result = await showModalBottomSheet<_CreatePageInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreatePageSheet(),
    );

    if (result == null) return;

    final pageId = await controller.createPage(name: result.name);
    if (!mounted) return;
    if (pageId == null) {
      await _showPageLimitReachedDialog();
      return;
    }
    context.go('/controller?pageId=$pageId');
  }

  Future<String?> _showRenameDialog(
      BuildContext context, String initial) async {
    final textController = TextEditingController(text: initial);

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename Page'),
          content: TextField(controller: textController, autofocus: true),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    textController.dispose();
    return value;
  }

  Future<bool> _confirmDeletePageDialog(
    BuildContext context,
    ControllerPage page,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Page?'),
          content: Text('Delete "${page.name}"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  bool _isPremiumOnlyPage(ControllerPage page) {
    final normalizedId = page.id.trim().toLowerCase();
    final normalizedName = page.name.trim().toLowerCase();
    return normalizedId == 'emergency' || normalizedName == 'emergency';
  }

  Future<void> _showPageLimitReachedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Page limit reached'),
          content: const Text(
            'Free users can create only 1 deck page. Upgrade to Premium to unlock unlimited pages.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await showPremiumUpgradeModal(
                  context,
                  highlightedFeature: PremiumFeature.unlimitedPages,
                );
              },
              child: const Text('Upgrade to Premium'),
            ),
          ],
        );
      },
    );
  }
}

class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({required this.page});

  final ControllerPage page;

  @override
  Widget build(BuildContext context) {
    final rows = page.rows.clamp(1, 3);
    final cols = page.columns.clamp(1, 3);
    final cells = (rows * cols).clamp(1, 9);
    final active = page.buttonCount.clamp(0, cells);

    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.7),
        ),
      ),
      child: GridView.builder(
        itemCount: cells,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemBuilder: (_, index) {
          final isActive = index < active;
          return Container(
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF137FEC).withValues(alpha: 0.45)
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        },
      ),
    );
  }
}

class _AddNewPageButton extends StatelessWidget {
  const _AddNewPageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF137FEC);

    return Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.add_circle, color: accent),
              const SizedBox(width: 8),
              Text(
                'Add New Page',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: accent,
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

class _LockedPagePreviewCard extends StatelessWidget {
  const _LockedPagePreviewCard({
    required this.pageNumber,
    required this.onTap,
  });

  final int pageNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.76,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
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
                Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Page $pageNumber',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const ProBadge(compact: true),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Premium page slot. Unlock unlimited pages and custom deck layouts.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
        ),
      ),
    );
  }
}

class _PagePremiumPreviewSheet extends StatelessWidget {
  const _PagePremiumPreviewSheet({
    required this.title,
    required this.description,
    required this.bullets,
  });

  final String title;
  final String description;
  final List<String> bullets;

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
                  Expanded(
                    child: Text(
                      title,
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
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              ...bullets.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
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

class _CreatePageInput {
  const _CreatePageInput({required this.name});

  final String name;
}

class _CreatePageSheet extends StatefulWidget {
  const _CreatePageSheet();

  @override
  State<_CreatePageSheet> createState() => _CreatePageSheetState();
}

class _CreatePageSheetState extends State<_CreatePageSheet> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                const SizedBox(height: 12),
                Text(
                  'Create New Page',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Page Name',
                    hintText: 'e.g. Gameplay View',
                  ),
                ),
                const SizedBox(height: 16),
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
                        onPressed: () {
                          Navigator.of(context).pop(
                            _CreatePageInput(name: _nameController.text),
                          );
                        },
                        child: const Text('Create Page'),
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
