import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../../core/utils/responsive.dart';
import '../../../../domain/entities/button_action.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/controller_button.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/obs_runtime_state.dart';
import '../../../../domain/entities/premium_feature.dart';
import '../../../../domain/entities/recording_status.dart';
import '../../../../domain/entities/scene_preview_mode.dart';
import '../../../../domain/entities/stream_status.dart';
import '../../../../shared/extensions/context_extensions.dart';
import '../../../../shared/extensions/duration_extensions.dart';
import '../../../../shared/state/app_engagement_controller.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/state/deck_button_runtime_state.dart';
import '../../../../shared/volunteer/volunteer_mode_policy.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/deck_button_grid.dart';
import '../../../../shared/widgets/page_indicator.dart';
import '../../../../shared/widgets/page_helper_text.dart';
import '../../../../shared/widgets/premium_upgrade_modal.dart';
import '../controllers/controller_controller.dart';
import '../models/controller_alert_banner.dart';

class ControllerScreen extends ConsumerStatefulWidget {
  const ControllerScreen({super.key, this.initialPageId});

  final String? initialPageId;

  @override
  ConsumerState<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends ConsumerState<ControllerScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final GlobalKey _connectToObsKey = GlobalKey();
  final GlobalKey _editModeKey = GlobalKey();
  final GlobalKey _controlTabKey = GlobalKey();
  final GlobalKey _pagesTabKey = GlobalKey();
  final GlobalKey _macrosTabKey = GlobalKey();
  final GlobalKey _monitorTabKey = GlobalKey();
  final GlobalKey _settingsTabKey = GlobalKey();
  bool _appliedInitialPage = false;
  int _lastSyncedPageIndex = 0;
  bool _tutorialShowing = false;
  bool _tabletPageListOpen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(controllerControllerProvider.notifier).setAppForeground(true);
    });
  }

  @override
  void didUpdateWidget(covariant ControllerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPageId != widget.initialPageId) {
      _appliedInitialPage = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(controllerControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        controller.setAppForeground(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        controller.setAppForeground(false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(controllerControllerProvider);
    final controller = ref.read(controllerControllerProvider.notifier);
    final volunteerMode = ref.watch(volunteerModeProvider);
    final scenePreviewMode = ref.watch(scenePreviewModeProvider);
    final premium = ref.watch(premiumControllerProvider);
    final engagement = ref.watch(appEngagementControllerProvider);
    final isEditMode = !volunteerMode &&
        state.interactionMode == ControllerInteractionMode.edit;

    if (volunteerMode &&
        state.interactionMode == ControllerInteractionMode.edit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        controller.setInteractionMode(ControllerInteractionMode.control);
      });
    }

    if (!_appliedInitialPage && state.pages.isNotEmpty) {
      _appliedInitialPage = true;
      if (widget.initialPageId != null) {
        final targetIndex =
            state.pages.indexWhere((page) => page.id == widget.initialPageId);
        if (targetIndex >= 0 && targetIndex != state.currentPageIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            controller.setPageIndex(targetIndex);
          });
        }
      }
    }

    _syncPageView(state.currentPageIndex);
    _scheduleTutorialIfNeeded(
      engagement: engagement,
      volunteerMode: volunteerMode,
    );

    final page = state.currentPage;
    final obsState = state.obsState;
    final quickControls = controller.quickControlButtons();
    final useTabletLayout = !context.isMobile;

    final volunteerBannerWidget =
        volunteerMode ? const _VolunteerModeBanner() : const SizedBox.shrink();
    final alertBannerWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: state.banner == null
          ? const SizedBox.shrink()
          : _ControllerAlertStrip(
              banner: state.banner!,
              onDismiss:
                  state.banner!.dismissible ? controller.dismissBanner : null,
            ),
    );
    final editModeBannerWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: isEditMode
          ? _EditModeBanner(
              onExit: controller.toggleInteractionMode,
            )
          : const SizedBox.shrink(),
    );
    final quickControlsWidget = _QuickControlsStrip(
      buttons: quickControls,
      resolveState: controller.resolveButtonState,
      forceDisabled: isEditMode,
      isTabletLayout: useTabletLayout,
      onTap: (button) {
        unawaited(_onButtonTap(controller, button));
      },
      onLongPress: (button) {
        unawaited(_onButtonLongPress(controller, button));
      },
    );
    final controllerHelperText = PageHelperText(
      text: isEditMode
          ? 'Control your OBS setup with custom buttons. Tap a button to select it. Long-press a button to edit it.'
          : 'Control your OBS setup with custom buttons. Tap to run an action. Enter Edit Mode to long-press a button and edit it.',
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          _isEmergencyPage(page) && !premium.isPremium
              ? '${page?.name ?? 'Emergency'} (PRO)'
              : (page?.name ?? 'Controller'),
        ),
        actions: <Widget>[
          if (!volunteerMode)
            SizedBox(
              key: _connectToObsKey,
              child: IconButton(
                icon: const Icon(Icons.wifi_tethering),
                tooltip: 'Connection',
                onPressed: () => context.go('/connection'),
              ),
            ),
          _HeaderStatusStrip(
            obsState: obsState,
          ),
          if (!volunteerMode)
            SizedBox(
              key: _editModeKey,
              child: IconButton(
                icon: Icon(isEditMode ? Icons.check : Icons.edit_outlined),
                tooltip: isEditMode ? 'Exit Edit Mode' : 'Enter Edit Mode',
                onPressed: controller.toggleInteractionMode,
              ),
            ),
          if (!volunteerMode)
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Create New Page',
              onPressed: () {
                unawaited(_openCreatePageSheet(controller));
              },
            ),
          if (scenePreviewMode != ScenePreviewMode.off)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Scene Previews',
              onPressed: () {
                unawaited(_onRefreshScenePreviews(controller));
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : useTabletLayout
                ? _TabletControllerLayout(
                    pageHelperText: controllerHelperText,
                    volunteerBanner: volunteerBannerWidget,
                    alertBanner: alertBannerWidget,
                    editModeBanner: editModeBannerWidget,
                    quickControls: quickControlsWidget,
                    pages: state.pages,
                    currentPageIndex: state.currentPageIndex,
                    obsState: obsState,
                    volunteerMode: volunteerMode,
                    onPageSelected: controller.setPageIndex,
                    onCreatePage: volunteerMode
                        ? null
                        : () {
                            unawaited(_openCreatePageSheet(controller));
                          },
                    pageContentBuilder: (page) => _buildPageContent(
                      page: page,
                      controller: controller,
                      state: state,
                      volunteerMode: volunteerMode,
                      isEditMode: isEditMode,
                      useTabletLayout: true,
                      pageListOpen: _tabletPageListOpen,
                    ),
                    pageListOpen: _tabletPageListOpen,
                    onTogglePageList: () {
                      setState(() {
                        _tabletPageListOpen = !_tabletPageListOpen;
                      });
                    },
                  )
                : _PhoneControllerLayout(
                    pageHelperText: controllerHelperText,
                    volunteerBanner: volunteerBannerWidget,
                    alertBanner: alertBannerWidget,
                    editModeBanner: editModeBannerWidget,
                    quickControls: quickControlsWidget,
                    pages: state.pages,
                    currentPageIndex: state.currentPageIndex,
                    pageController: _pageController,
                    onPageChanged: controller.setPageIndex,
                    onCreatePage: volunteerMode
                        ? null
                        : () {
                            unawaited(_openCreatePageSheet(controller));
                          },
                    pageContentBuilder: (page) => _buildPageContent(
                      page: page,
                      controller: controller,
                      state: state,
                      volunteerMode: volunteerMode,
                      isEditMode: isEditMode,
                      useTabletLayout: false,
                      pageListOpen: true,
                    ),
                    onDotTap: controller.setPageIndex,
                  ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppBottomNavTab.control,
        tabKeys: <AppBottomNavTab, GlobalKey>{
          AppBottomNavTab.control: _controlTabKey,
          AppBottomNavTab.pages: _pagesTabKey,
          AppBottomNavTab.macros: _macrosTabKey,
          AppBottomNavTab.monitor: _monitorTabKey,
          AppBottomNavTab.settings: _settingsTabKey,
        },
      ),
    );
  }

  Widget _buildPageContent({
    required ControllerPage page,
    required ControllerController controller,
    required ControllerScreenState state,
    required bool volunteerMode,
    required bool isEditMode,
    required bool useTabletLayout,
    required bool pageListOpen,
  }) {
    final obsState = state.obsState;
    final pageButtons = volunteerMode
        ? page.buttons
            .where(
              (button) => !VolunteerModePolicy.isRestrictedButtonAction(
                button.action.type,
              ),
            )
            .toList(growable: false)
        : page.buttons;
    final isEmergencyPage = _isEmergencyPage(page);
    final isScenesPage = _isScenesPage(page);
    final columns = _resolveColumnsForLayout(
      context,
      page,
      useTabletLayout: useTabletLayout,
      pageListOpen: pageListOpen,
    );

    final showScenesDisconnectedState =
        isScenesPage && obsState.connectionStatus != ConnectionStatus.connected;
    final showScenesLoadingState = isScenesPage &&
        obsState.connectionStatus == ConnectionStatus.connected &&
        (obsState.scenes.isEmpty ||
            (obsState.scenes.isNotEmpty && pageButtons.isEmpty));

    return ListView(
      padding: Responsive.pagePadding(context),
      children: <Widget>[
        SizedBox(height: isEmergencyPage ? 2 : 8),
        if (context.isDesktop && !useTabletLayout) ...<Widget>[
          Row(
            children: <Widget>[
              IconButton.filledTonal(
                onPressed: state.currentPageIndex > 0
                    ? () => controller.setPageIndex(state.currentPageIndex - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: state.currentPageIndex < state.pages.length - 1
                    ? () => controller.setPageIndex(state.currentPageIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (showScenesDisconnectedState)
          _ScenesDisconnectedState(
            onConnect: () => context.go('/connection'),
          )
        else if (showScenesLoadingState)
          const _ScenesLoadingState()
        else
          DeckButtonGrid(
            buttons: pageButtons,
            columns: columns,
            rows: page.rows,
            childAspectRatio: isEmergencyPage
                ? (useTabletLayout ? 1.05 : 1.1)
                : (useTabletLayout ? 1.02 : 1),
            showEmptySlots: isEditMode && !isScenesPage,
            resolveButtonState: controller.resolveButtonState,
            selectedButtonId: state.selectedButtonId,
            showHoldBadges: !isEditMode,
            thumbnailForButton: controller.sceneThumbnailForButton,
            allowDisabledButtonInteraction: isEditMode,
            onButtonTap: (button) {
              unawaited(_onButtonTap(controller, button));
            },
            onButtonLongPress: (button) {
              unawaited(_onButtonLongPress(controller, button));
            },
            onEmptySlotTap: isEditMode && !isScenesPage
                ? (slotIndex) {
                    unawaited(
                      _onAddSlotTap(
                        controller,
                        page,
                        slotIndex,
                      ),
                    );
                  }
                : null,
          ),
        if (!isEditMode &&
            !showScenesDisconnectedState &&
            !showScenesLoadingState &&
            pageButtons.isEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            isScenesPage
                ? 'Connect to OBS to import scenes, or refresh to load scene data.'
                : volunteerMode
                    ? 'All controls on this page are restricted in Volunteer Mode.'
                    : 'This page is empty. Tap Edit to add a button.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }

  void _scheduleTutorialIfNeeded({
    required AppEngagementState engagement,
    required bool volunteerMode,
  }) {
    if (_tutorialShowing) return;
    if (!engagement.ready || !engagement.tutorialPending) return;
    if (engagement.onboardingActive || volunteerMode) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tutorialShowing) return;
      _startTutorial();
    });
  }

  Future<void> _startTutorial() async {
    final obsState = ref.read(controllerControllerProvider).obsState;
    final includeConnectStep =
        obsState.connectionStatus != ConnectionStatus.connected;
    final targets =
        _buildTutorialTargets(includeConnectStep: includeConnectStep);
    if (targets.isEmpty) return;

    _tutorialShowing = true;
    final engagementController =
        ref.read(appEngagementControllerProvider.notifier);
    await engagementController.consumeTutorialPending();
    await engagementController.setOnboardingActive(true);
    if (!mounted) return;

    TutorialCoachMark(
      targets: targets,
      textSkip: 'SKIP',
      colorShadow: Colors.black,
      opacityShadow: 0.82,
      hideSkip: true,
      pulseEnable: false,
      focusAnimationDuration: const Duration(milliseconds: 180),
      unFocusAnimationDuration: const Duration(milliseconds: 140),
      onFinish: () {
        _endTutorial();
      },
      onSkip: () {
        _endTutorial();
        return true;
      },
    ).show(context: context);
  }

  List<TargetFocus> _buildTutorialTargets({
    required bool includeConnectStep,
  }) {
    final targets = <TargetFocus>[];

    void addTarget({
      required String id,
      required GlobalKey key,
      required String title,
      required String description,
      required IconData icon,
      ContentAlign align = ContentAlign.bottom,
      bool isFinalStep = false,
      List<String> highlights = const <String>[],
    }) {
      if (key.currentContext == null) return;
      targets.add(
        TargetFocus(
          identify: id,
          keyTarget: key,
          contents: <TargetContent>[
            TargetContent(
              align: align,
              builder: (context, controller) {
                return _TutorialCard(
                  title: title,
                  description: description,
                  icon: icon,
                  tutorialController: controller,
                  isFinalStep: isFinalStep,
                  highlights: highlights,
                );
              },
            ),
          ],
        ),
      );
    }

    if (includeConnectStep) {
      addTarget(
        id: 'connect_obs',
        key: _connectToObsKey,
        title: 'Connect to OBS',
        description:
            'Use this to link DeckPilot with OBS on your computer before controlling anything.',
        icon: Icons.link,
        highlights: const <String>[
          'Try Find OBS Automatically first, then QR scan, then Manual Setup.',
          'After connection, scenes and input states sync in real time.',
        ],
      );
    }
    addTarget(
      id: 'control_tab',
      key: _controlTabKey,
      title: 'Control tab',
      description:
          'Use this tab for live control during streaming. Button presses send actions directly to OBS.',
      icon: Icons.sports_esports,
      align: ContentAlign.top,
      highlights: const <String>[
        'Switch scenes, run assigned actions, and use quick controls at the top.',
        'Button states (LIVE/REC/mute/visibility) follow real OBS state.',
      ],
    );
    addTarget(
      id: 'pages_tab',
      key: _pagesTabKey,
      title: 'Pages tab',
      description:
          'Use this tab to organize controller layouts. Keep pages focused by workflow.',
      icon: Icons.layers,
      align: ContentAlign.top,
      highlights: const <String>[
        'Create, rename, reorder, duplicate, and delete pages.',
        'Scenes page syncs from OBS; custom pages are fully configurable.',
      ],
    );
    addTarget(
      id: 'macros_tab',
      key: _macrosTabKey,
      title: 'Macros tab',
      description:
          'Use this tab to build and manage multi-step automations for one-tap execution.',
      icon: Icons.bolt,
      align: ContentAlign.top,
      highlights: const <String>[
        'Add ordered steps, delays, and test macro behavior safely.',
        'Assign saved macros to controller buttons and emergency actions.',
      ],
    );
    addTarget(
      id: 'monitor_tab',
      key: _monitorTabKey,
      title: 'Monitor tab',
      description:
          'Use this tab to monitor live stream health and detect issues early.',
      icon: Icons.dashboard,
      align: ContentAlign.top,
      highlights: const <String>[
        'Track bitrate, dropped/skipped frames, congestion, and connection health.',
        'Warnings here help you react quickly before viewers notice problems.',
      ],
    );
    addTarget(
      id: 'settings_tab',
      key: _settingsTabKey,
      title: 'Settings tab',
      description:
          'Use this tab for app preferences, setup tools, and operator assistance options.',
      icon: Icons.settings,
      align: ContentAlign.top,
      highlights: const <String>[
        'Manage saved OBS connections, volunteer mode, and tutorial/review options.',
        'Open Help/FAQ when troubleshooting setup or control behavior.',
      ],
    );
    addTarget(
      id: 'edit_mode',
      key: _editModeKey,
      title: 'Edit mode',
      description:
          'Use Edit Mode for customization. OBS actions are disabled while editing.',
      icon: Icons.edit,
      isFinalStep: true,
      highlights: const <String>[
        'Long-press buttons to open Button Editor and change action mappings.',
        'Exit Edit Mode to return to live control execution.',
      ],
    );

    return targets;
  }

  Future<void> _endTutorial() async {
    _tutorialShowing = false;
    if (!mounted) return;
    await ref.read(appEngagementControllerProvider.notifier).completeTutorial();
  }

  void _syncPageView(int targetIndex) {
    if (_lastSyncedPageIndex == targetIndex) return;
    _lastSyncedPageIndex = targetIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      final currentIndex =
          _pageController.page?.round() ?? _pageController.initialPage;
      if (currentIndex == targetIndex) return;

      _pageController.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  int _resolveColumns(BuildContext context, ControllerPage page) {
    final type = Responsive.deviceType(context);
    final baseColumns = page.columns;
    if (_isEmergencyPage(page)) {
      return switch (type) {
        DeviceType.mobile => 4,
        DeviceType.tablet => 4,
        DeviceType.desktop => 5,
      };
    }
    switch (type) {
      case DeviceType.mobile:
        return baseColumns.clamp(3, 4).toInt();
      case DeviceType.tablet:
        return baseColumns.clamp(4, 6).toInt();
      case DeviceType.desktop:
        return baseColumns.clamp(4, 8).toInt();
    }
  }

  int _resolveColumnsForLayout(
    BuildContext context,
    ControllerPage page, {
    required bool useTabletLayout,
    required bool pageListOpen,
  }) {
    final base = _resolveColumns(context, page);
    if (!useTabletLayout) return base;

    if (_isEmergencyPage(page)) {
      final maxColumns = pageListOpen ? 5 : 6;
      return base.clamp(4, maxColumns).toInt();
    }

    final bonusColumns = pageListOpen
        ? (context.isDesktop ? 1 : 0)
        : (context.isDesktop ? 2 : 1);
    final maxColumns = pageListOpen ? 7 : 8;
    final widened = base + bonusColumns;
    return widened.clamp(4, maxColumns).toInt();
  }

  bool _isEmergencyPage(ControllerPage? page) {
    if (page == null) return false;
    final id = page.id.trim().toLowerCase();
    final name = page.name.trim().toLowerCase();
    return id == 'emergency' || name == 'emergency';
  }

  bool _isScenesPage(ControllerPage? page) {
    if (page == null) return false;
    final id = page.id.trim().toLowerCase();
    final name = page.name.trim().toLowerCase();
    return id == 'scenes' || name == 'scenes';
  }

  Future<void> _onButtonTap(
    ControllerController controller,
    ControllerButton button,
  ) async {
    final outcome = await controller.onButtonTap(button);
    if (!mounted) return;

    if (outcome == ControllerButtonInteractionOutcome.holdRequired) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Hold this button to execute its action.'),
            duration: Duration(milliseconds: 1300),
          ),
        );
      return;
    }

    if (outcome == ControllerButtonInteractionOutcome.blockedByPremium) {
      await showPremiumUpgradeModal(
        context,
        highlightedFeature: _featureForButton(button),
      );
      return;
    }

    if (outcome == ControllerButtonInteractionOutcome.blockedByVolunteerMode) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Volunteer Mode: this control is disabled.'),
            duration: Duration(milliseconds: 1400),
          ),
        );
    }
  }

  Future<void> _onButtonLongPress(
    ControllerController controller,
    ControllerButton button,
  ) async {
    final outcome = await controller.onButtonLongPress(button);
    if (!mounted) return;

    if (outcome == ControllerButtonInteractionOutcome.openEditor) {
      await context.push('/button-editor?buttonId=${button.id}');
      if (!mounted) return;
      await controller.refreshPages();
      return;
    }

    if (outcome == ControllerButtonInteractionOutcome.blockedByPremium) {
      await showPremiumUpgradeModal(
        context,
        highlightedFeature: _featureForButton(button),
      );
      return;
    }

    if (outcome == ControllerButtonInteractionOutcome.blockedByVolunteerMode) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Volunteer Mode: this control is disabled.'),
            duration: Duration(milliseconds: 1400),
          ),
        );
    }
  }

  Future<void> _onAddSlotTap(
    ControllerController controller,
    ControllerPage page,
    int slotIndex,
  ) async {
    final uri = Uri(
      path: '/button-editor',
      queryParameters: <String, String>{
        'pageId': page.id,
        'slot': '$slotIndex',
      },
    );

    await context.push(uri.toString());
    if (!mounted) return;
    await controller.refreshPages();
  }

  Future<void> _openCreatePageSheet(
    ControllerController controller,
  ) async {
    if (ref.read(volunteerModeProvider)) return;

    final result = await showModalBottomSheet<_CreateControllerPageInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateControllerPageSheet(),
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

  Future<void> _onRefreshScenePreviews(
    ControllerController controller,
  ) async {
    await controller.refreshScenePreviewsManually();
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Scene previews refreshed.'),
          duration: Duration(milliseconds: 1200),
        ),
      );
  }

  PremiumFeature _featureForButton(ControllerButton button) {
    final raw = button.action.metadata['premiumFeature'] as String?;
    switch (raw) {
      case 'unlimitedScenes':
        return PremiumFeature.unlimitedScenes;
      case 'emergencyPage':
        return PremiumFeature.emergencyPage;
    }
    if (button.action.type == ButtonActionType.runMacro) {
      return PremiumFeature.macros;
    }
    return PremiumFeature.unlimitedScenes;
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

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.tutorialController,
    required this.isFinalStep,
    this.highlights = const <String>[],
  });

  final String title;
  final String description;
  final IconData icon;
  final TutorialCoachMarkController tutorialController;
  final bool isFinalStep;
  final List<String> highlights;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (highlights.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            ...highlights.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.circle, size: 6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: tutorialController.skip,
                child: const Text('Skip'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: tutorialController.next,
                  child: Text(isFinalStep ? 'Done' : 'Next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isFinalStep
                ? 'Tap Done to finish or Skip to close.'
                : 'Use Next to continue or Skip to close.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _PhoneControllerLayout extends StatelessWidget {
  const _PhoneControllerLayout({
    required this.pageHelperText,
    required this.volunteerBanner,
    required this.alertBanner,
    required this.editModeBanner,
    required this.quickControls,
    required this.pages,
    required this.currentPageIndex,
    required this.pageController,
    required this.onPageChanged,
    required this.onCreatePage,
    required this.pageContentBuilder,
    required this.onDotTap,
  });

  final Widget pageHelperText;
  final Widget volunteerBanner;
  final Widget alertBanner;
  final Widget editModeBanner;
  final Widget quickControls;
  final List<ControllerPage> pages;
  final int currentPageIndex;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onCreatePage;
  final Widget Function(ControllerPage page) pageContentBuilder;
  final ValueChanged<int> onDotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        pageHelperText,
        volunteerBanner,
        alertBanner,
        editModeBanner,
        quickControls,
        if (pages.isEmpty)
          Expanded(
            child: _NoPagesState(onCreatePage: onCreatePage),
          )
        else
          Expanded(
            child: PageView.builder(
              controller: pageController,
              onPageChanged: onPageChanged,
              itemCount: pages.length,
              itemBuilder: (_, index) => pageContentBuilder(pages[index]),
            ),
          ),
        if (pages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PageIndicator(
              count: pages.length,
              currentIndex: currentPageIndex,
              onDotTap: onDotTap,
            ),
          ),
      ],
    );
  }
}

class _TabletControllerLayout extends StatelessWidget {
  const _TabletControllerLayout({
    required this.pageHelperText,
    required this.volunteerBanner,
    required this.alertBanner,
    required this.editModeBanner,
    required this.quickControls,
    required this.pages,
    required this.currentPageIndex,
    required this.obsState,
    required this.volunteerMode,
    required this.onPageSelected,
    required this.onCreatePage,
    required this.pageContentBuilder,
    required this.pageListOpen,
    required this.onTogglePageList,
  });

  final Widget pageHelperText;
  final Widget volunteerBanner;
  final Widget alertBanner;
  final Widget editModeBanner;
  final Widget quickControls;
  final List<ControllerPage> pages;
  final int currentPageIndex;
  final ObsRuntimeState obsState;
  final bool volunteerMode;
  final ValueChanged<int> onPageSelected;
  final VoidCallback? onCreatePage;
  final Widget Function(ControllerPage page) pageContentBuilder;
  final bool pageListOpen;
  final VoidCallback onTogglePageList;

  @override
  Widget build(BuildContext context) {
    final page = (currentPageIndex >= 0 && currentPageIndex < pages.length)
        ? pages[currentPageIndex]
        : null;

    return Column(
      children: <Widget>[
        pageHelperText,
        volunteerBanner,
        alertBanner,
        editModeBanner,
        const SizedBox(height: 4),
        _TabletStatusOverview(obsState: obsState),
        quickControls,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (pageListOpen) ...<Widget>[
                  SizedBox(
                    width: context.isDesktop ? 320 : 260,
                    child: _TabletPageSidebar(
                      pages: pages,
                      currentPageIndex: currentPageIndex,
                      obsState: obsState,
                      volunteerMode: volunteerMode,
                      onPageSelected: onPageSelected,
                      onCreatePage: onCreatePage,
                      onClose: onTogglePageList,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        _TabletContentHeader(
                          page: page,
                          pageCount: pages.length,
                          currentPageIndex: currentPageIndex,
                          pageListOpen: pageListOpen,
                          onTogglePageList: onTogglePageList,
                        ),
                        Divider(
                          height: 1,
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.35),
                        ),
                        Expanded(
                          child: page == null
                              ? _NoPagesState(onCreatePage: onCreatePage)
                              : pageContentBuilder(page),
                        ),
                        if (!pageListOpen && pages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: PageIndicator(
                              count: pages.length,
                              currentIndex: currentPageIndex,
                              onDotTap: onPageSelected,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletStatusOverview extends StatelessWidget {
  const _TabletStatusOverview({required this.obsState});

  final ObsRuntimeState obsState;

  @override
  Widget build(BuildContext context) {
    final streamLabel = switch (obsState.streamStatus) {
      StreamStatus.live => 'Live',
      StreamStatus.starting => 'Starting',
      StreamStatus.stopping => 'Stopping',
      StreamStatus.error => 'Error',
      StreamStatus.offline => 'Offline',
    };
    final recLabel = switch (obsState.recordingStatus) {
      RecordingStatus.recording => 'Recording',
      RecordingStatus.paused => 'Paused',
      RecordingStatus.starting => 'Starting',
      RecordingStatus.stopping => 'Stopping',
      RecordingStatus.error => 'Error',
      RecordingStatus.stopped => 'Stopped',
    };
    final connected = obsState.connectionStatus == ConnectionStatus.connected;
    final activeFpsLabel =
        connected ? 'FPS ${obsState.activeFps.toStringAsFixed(2)}' : 'FPS --';
    final cpuLabel = connected
        ? 'CPU ${obsState.cpuUsagePercent.toStringAsFixed(1)}%'
        : 'CPU --';
    final netWarning = obsState.outputReconnecting ||
        obsState.outputCongestion >= 0.15 ||
        obsState.outputSkippedFramesPercent >= 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: <Widget>[
          _TabletStatusChip(
            icon: Icons.sensors,
            label: connected ? 'OBS Connected' : 'OBS Offline',
            tone:
                connected ? Colors.green : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          _TabletStatusChip(
            icon: Icons.stream,
            label: streamLabel,
            tone: obsState.streamStatus == StreamStatus.live
                ? Colors.red
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          _TabletStatusChip(
            icon: Icons.fiber_manual_record,
            label: recLabel,
            tone: (obsState.recordingStatus == RecordingStatus.recording ||
                    obsState.recordingStatus == RecordingStatus.paused)
                ? Colors.redAccent
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          if (obsState.virtualCameraActive) ...<Widget>[
            const SizedBox(width: 8),
            const _TabletStatusChip(
              icon: Icons.videocam,
              label: 'Virtual Cam',
              tone: Colors.cyan,
            ),
          ],
          if (obsState.studioModeEnabled) ...<Widget>[
            const SizedBox(width: 8),
            const _TabletStatusChip(
              icon: Icons.slideshow,
              label: 'Studio Mode',
              tone: Colors.blueAccent,
            ),
          ],
          if (netWarning) ...<Widget>[
            const SizedBox(width: 8),
            const _TabletStatusChip(
              icon: Icons.warning_amber_rounded,
              label: 'Network Warning',
              tone: Colors.orange,
            ),
          ],
          const SizedBox(width: 8),
          _TabletStatusChip(
            icon: Icons.speed,
            label: cpuLabel,
            tone: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _TabletStatusChip(
            icon: Icons.animation_outlined,
            label: activeFpsLabel,
            tone: Theme.of(context).colorScheme.primary,
          ),
          if (obsState.streamStatus == StreamStatus.live) ...<Widget>[
            const SizedBox(width: 8),
            _TabletStatusChip(
              icon: Icons.timer_outlined,
              label: obsState.streamTimecode ?? obsState.uptime.toHms(),
              tone: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _TabletStatusChip extends StatelessWidget {
  const _TabletStatusChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _TabletContentHeader extends StatelessWidget {
  const _TabletContentHeader({
    required this.page,
    required this.pageCount,
    required this.currentPageIndex,
    required this.pageListOpen,
    required this.onTogglePageList,
  });

  final ControllerPage? page;
  final int pageCount;
  final int currentPageIndex;
  final bool pageListOpen;
  final VoidCallback onTogglePageList;

  @override
  Widget build(BuildContext context) {
    final pageLabel = page?.name ?? 'No Page Selected';
    final pagePosition =
        pageCount == 0 ? '0/0' : '${currentPageIndex + 1}/$pageCount';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: onTogglePageList,
            icon: Icon(
              pageListOpen
                  ? Icons.view_sidebar_outlined
                  : Icons.view_sidebar_rounded,
            ),
            tooltip: pageListOpen ? 'Hide Page List' : 'Show Page List',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  pageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  pageListOpen
                      ? 'Page list open'
                      : 'Page list hidden. Grid expanded for tablet view.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.42),
            ),
            child: Text(
              pagePosition,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletPageSidebar extends StatelessWidget {
  const _TabletPageSidebar({
    required this.pages,
    required this.currentPageIndex,
    required this.obsState,
    required this.volunteerMode,
    required this.onPageSelected,
    required this.onCreatePage,
    required this.onClose,
  });

  final List<ControllerPage> pages;
  final int currentPageIndex;
  final ObsRuntimeState obsState;
  final bool volunteerMode;
  final ValueChanged<int> onPageSelected;
  final VoidCallback? onCreatePage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: 0.35,
              ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Page List',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.view_sidebar_outlined),
                  tooltip: 'Hide Page List',
                ),
                if (onCreatePage != null)
                  IconButton.filledTonal(
                    onPressed: onCreatePage,
                    icon: const Icon(Icons.add),
                    tooltip: 'Create Page',
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: pages.isEmpty
                  ? Center(
                      child: Text(
                        'No pages yet',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: pages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, index) {
                        final page = pages[index];
                        final selected = index == currentPageIndex;
                        final tone = selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant;
                        return Material(
                          color: selected
                              ? tone.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onPageSelected(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    _pageIcon(page),
                                    size: 18,
                                    color: tone,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      page.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: selected
                                                ? tone
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            _TabletMonitorMiniCards(obsState: obsState),
            if (volunteerMode) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Volunteer mode enabled',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _pageIcon(ControllerPage page) {
    final normalized = page.name.trim().toLowerCase();
    if (normalized.contains('scene')) return Icons.movie_outlined;
    if (normalized.contains('audio')) return Icons.graphic_eq;
    if (normalized.contains('macro')) return Icons.bolt;
    if (normalized.contains('emergency')) return Icons.warning_amber_outlined;
    return Icons.dashboard_outlined;
  }
}

class _TabletMonitorMiniCards extends StatelessWidget {
  const _TabletMonitorMiniCards({required this.obsState});

  final ObsRuntimeState obsState;

  @override
  Widget build(BuildContext context) {
    final networkLabel = obsState.outputReconnecting
        ? 'Reconnecting'
        : (obsState.outputCongestion >= 0.15 ? 'Unstable' : 'Stable');
    return Column(
      children: <Widget>[
        _MiniMetricTile(
          label: 'Bitrate',
          value: '${obsState.bitrateKbps} kbps',
          icon: Icons.speed,
        ),
        const SizedBox(height: 6),
        _MiniMetricTile(
          label: 'Dropped',
          value: '${obsState.droppedFramesPercent.toStringAsFixed(1)}%',
          icon: Icons.error_outline,
        ),
        const SizedBox(height: 6),
        _MiniMetricTile(
          label: 'Network',
          value: networkLabel,
          icon: Icons.wifi,
        ),
      ],
    );
  }
}

class _MiniMetricTile extends StatelessWidget {
  const _MiniMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.38),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _NoPagesState extends StatelessWidget {
  const _NoPagesState({this.onCreatePage});

  final VoidCallback? onCreatePage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.dashboard_customize_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No pages yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a page to add custom buttons, or connect to OBS to sync scenes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (onCreatePage != null) ...<Widget>[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onCreatePage,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Create Page'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScenesDisconnectedState extends StatelessWidget {
  const _ScenesDisconnectedState({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.sensors_off_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                'No OBS scenes loaded',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Connect to OBS to load your real scenes, audio inputs, and controls.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Connect to OBS'),
              ),
              const SizedBox(height: 8),
              Text(
                'Once connected, this page will show your real OBS scenes.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenesLoadingState extends StatelessWidget {
  const _ScenesLoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading OBS scenes...',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Fetching your real scene list from OBS.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderStatusStrip extends StatelessWidget {
  const _HeaderStatusStrip({
    required this.obsState,
  });

  final ObsRuntimeState obsState;

  @override
  Widget build(BuildContext context) {
    final connectionStatus = obsState.connectionStatus;
    final streamStatus = obsState.streamStatus;
    final recordingStatus = obsState.recordingStatus;
    final connectionTone = switch (connectionStatus) {
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
    final showRec = recordingStatus == RecordingStatus.recording ||
        recordingStatus == RecordingStatus.paused;
    final showNetworkWarning = streamStatus == StreamStatus.live &&
        (obsState.outputReconnecting ||
            obsState.outputCongestion >= 0.15 ||
            obsState.outputSkippedFramesPercent >= 1.0 ||
            obsState.droppedFramesPercent >= 1.0);
    final showPerformanceMetrics = MediaQuery.sizeOf(context).width >= 900 &&
        connectionStatus == ConnectionStatus.connected;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _HeaderStatusPill(label: 'OBS', tone: connectionTone),
          if (streamStatus == StreamStatus.live)
            const _HeaderStatusPill(
              label: 'LIVE',
              tone: Colors.redAccent,
            ),
          if (showRec)
            const _HeaderStatusPill(
              label: 'REC',
              tone: Colors.red,
            ),
          if (obsState.virtualCameraActive)
            const _HeaderStatusPill(
              label: 'CAM',
              tone: Colors.cyan,
            ),
          if (obsState.studioModeEnabled)
            const _HeaderStatusPill(
              label: 'STUDIO',
              tone: Colors.blueAccent,
            ),
          if (showNetworkWarning)
            const _HeaderStatusPill(
              label: 'NET',
              tone: Colors.orange,
            ),
          if (showPerformanceMetrics)
            _HeaderStatusPill(
              label: 'CPU ${obsState.cpuUsagePercent.toStringAsFixed(1)}%',
              tone: Theme.of(context).colorScheme.primary,
            ),
          if (showPerformanceMetrics)
            _HeaderStatusPill(
              label: 'FPS ${obsState.activeFps.toStringAsFixed(2)}',
              tone: Theme.of(context).colorScheme.primary,
            ),
          if (showPerformanceMetrics && streamStatus == StreamStatus.live)
            _HeaderStatusPill(
              label: obsState.streamTimecode ?? obsState.uptime.toHms(),
              tone: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

class _HeaderStatusPill extends StatelessWidget {
  const _HeaderStatusPill({
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tone,
                  letterSpacing: 0.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _ControllerAlertStrip extends StatelessWidget {
  const _ControllerAlertStrip({
    required this.banner,
    this.onDismiss,
  });

  final ControllerAlertBanner banner;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = banner.tone(colorScheme);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(banner.icon(), color: tone, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              banner.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

class _QuickControlsStrip extends StatelessWidget {
  const _QuickControlsStrip({
    required this.buttons,
    required this.resolveState,
    required this.onTap,
    required this.onLongPress,
    required this.forceDisabled,
    required this.isTabletLayout,
  });

  final List<ControllerButton> buttons;
  final DeckButtonRuntimeState Function(ControllerButton button) resolveState;
  final ValueChanged<ControllerButton> onTap;
  final ValueChanged<ControllerButton> onLongPress;
  final bool forceDisabled;
  final bool isTabletLayout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveButtons = buttons
        .where((button) => button.label.trim().isNotEmpty)
        .toList(growable: false);
    if (effectiveButtons.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasProtectedButtons =
        effectiveButtons.any((button) => button.longPressTrigger);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, isTabletLayout ? 8 : 4, 12, 6),
      child: Column(
        children: <Widget>[
          Row(
            children: effectiveButtons.asMap().entries.map((entry) {
              final index = entry.key;
              final button = entry.value;
              final state = resolveState(button);
              final effectiveState = DeckButtonRuntimeState(
                enabled: !forceDisabled && state.enabled,
                active: state.active,
                pending: state.pending,
                hasError: state.hasError,
              );
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == effectiveButtons.length - 1 ? 0 : 6,
                  ),
                  child: _QuickControlButton(
                    button: button,
                    state: effectiveState,
                    isTabletLayout: isTabletLayout,
                    onTap: () => onTap(button),
                    onLongPress: () => onLongPress(button),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          if (hasProtectedButtons) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hold protected controls to confirm.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickControlButton extends StatefulWidget {
  const _QuickControlButton({
    required this.button,
    required this.state,
    required this.isTabletLayout,
    required this.onTap,
    required this.onLongPress,
  });

  final ControllerButton button;
  final DeckButtonRuntimeState state;
  final bool isTabletLayout;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_QuickControlButton> createState() => _QuickControlButtonState();
}

class _QuickControlButtonState extends State<_QuickControlButton>
    with SingleTickerProviderStateMixin {
  static const Duration _holdProgressDuration = Duration(milliseconds: 480);
  static const Duration _holdResetDuration = Duration(milliseconds: 140);

  late final AnimationController _holdController;
  bool _showHoldProgress = false;
  bool _holdTriggered = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: _holdProgressDuration,
    );
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _QuickControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedAction =
        oldWidget.button.action.type != widget.button.action.type;
    final changedTarget =
        oldWidget.button.action.targetId != widget.button.action.targetId;
    final changedLongPress =
        oldWidget.button.longPressTrigger != widget.button.longPressTrigger;
    if (changedAction || changedTarget || changedLongPress) {
      _resetHoldProgress(immediate: true);
    }
  }

  void _startHoldProgress() {
    if (!widget.button.longPressTrigger ||
        !widget.state.enabled ||
        widget.state.pending) {
      return;
    }
    setState(() {
      _showHoldProgress = true;
      _holdTriggered = false;
    });
    _holdController.forward(from: 0);
  }

  void _markHoldTriggered() {
    if (!widget.button.longPressTrigger ||
        !widget.state.enabled ||
        widget.state.pending) {
      return;
    }
    _holdTriggered = true;
    _holdController.value = 1;
    widget.onLongPress();
    Future<void>.delayed(_holdResetDuration, () {
      if (!mounted) return;
      _resetHoldProgress(immediate: true);
    });
  }

  void _cancelHoldProgress() {
    if (_holdTriggered) return;
    _resetHoldProgress();
  }

  void _resetHoldProgress({bool immediate = false}) {
    if (!_showHoldProgress && _holdController.value == 0) return;
    if (immediate) {
      _holdController.stop();
      _holdController.value = 0;
      if (mounted) {
        setState(() {
          _showHoldProgress = false;
          _holdTriggered = false;
        });
      }
      return;
    }

    _holdController
        .animateBack(
      0,
      duration: _holdResetDuration,
      curve: Curves.easeOut,
    )
        .whenComplete(() {
      if (!mounted) return;
      setState(() {
        _showHoldProgress = false;
        _holdTriggered = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = _quickControlTone(
      button: widget.button,
      state: widget.state,
      colorScheme: colorScheme,
    );
    final enabled = widget.state.enabled && !widget.state.pending;
    final textColor = enabled ? colorScheme.onSurface : colorScheme.outline;
    final showHoldProgress = widget.button.longPressTrigger &&
        (_showHoldProgress || _holdController.value > 0);
    final buttonRadius = BorderRadius.circular(8);

    return Opacity(
      opacity: enabled ? 1 : 0.52,
      child: Material(
        color: tone.withValues(alpha: widget.state.active ? 0.14 : 0.05),
        borderRadius: buttonRadius,
        child: InkWell(
          onTap:
              enabled && !widget.button.longPressTrigger ? widget.onTap : null,
          onLongPress: enabled && widget.button.longPressTrigger
              ? _markHoldTriggered
              : null,
          onTapDown: enabled && widget.button.longPressTrigger
              ? (_) => _startHoldProgress()
              : null,
          onTapCancel: enabled && widget.button.longPressTrigger
              ? _cancelHoldProgress
              : null,
          onTapUp: enabled && widget.button.longPressTrigger
              ? (_) => _cancelHoldProgress()
              : null,
          borderRadius: buttonRadius,
          child: Container(
            height: widget.isTabletLayout ? 44 : 38,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: buttonRadius,
              border: Border.all(
                color: tone.withValues(alpha: 0.2),
                width: 0.7,
              ),
            ),
            child: Stack(
              children: <Widget>[
                if (showHoldProgress)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: buttonRadius,
                      child: AnimatedBuilder(
                        animation: _holdController,
                        builder: (context, _) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _holdController.value.clamp(0, 1),
                              child: Container(
                                color: tone.withValues(alpha: 0.2),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _quickIcon(widget.button.icon),
                        size: widget.isTabletLayout ? 16 : 14,
                        color: tone,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          widget.button.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: widget.isTabletLayout ? 12 : null,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.state.pending)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      ),
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

Color? _colorFromHex(String hex) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length != 6 && cleaned.length != 8) return null;
  final normalized = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return null;
  return Color(value);
}

IconData _quickIcon(String iconName) {
  switch (iconName) {
    case 'mic':
      return Icons.mic_rounded;
    case 'mic_off':
      return Icons.mic_off_outlined;
    case 'videocam':
      return Icons.videocam;
    case 'videocam_off':
      return Icons.videocam_off;
    case 'preview':
      return Icons.slideshow;
    case 'tune':
      return Icons.tune;
    case 'play_arrow':
      return Icons.play_arrow_rounded;
    case 'stop_circle':
      return Icons.stop_circle_outlined;
    case 'radio_button_checked':
      return Icons.radio_button_checked_outlined;
    case 'stop':
      return Icons.stop_rounded;
    default:
      return Icons.tune_rounded;
  }
}

Color _quickControlTone({
  required ControllerButton button,
  required DeckButtonRuntimeState state,
  required ColorScheme colorScheme,
}) {
  if (button.id == 'quick_mic') {
    if (button.action.type == ButtonActionType.unmute) {
      return Colors.green;
    }
    return Colors.orange;
  }

  if (button.action.type == ButtonActionType.enableStudioMode ||
      button.action.type == ButtonActionType.disableStudioMode ||
      button.action.type == ButtonActionType.toggleStudioMode) {
    return state.enabled ? Colors.blueAccent : colorScheme.onSurfaceVariant;
  }

  if (button.action.type == ButtonActionType.startStream ||
      button.action.type == ButtonActionType.startRecording ||
      button.action.type == ButtonActionType.startVirtualCamera ||
      button.action.type == ButtonActionType.enableStudioMode) {
    return state.enabled ? Colors.green : colorScheme.onSurfaceVariant;
  }

  if (button.action.type == ButtonActionType.stopStream ||
      button.action.type == ButtonActionType.stopRecording ||
      button.action.type == ButtonActionType.stopVirtualCamera ||
      button.action.type == ButtonActionType.disableStudioMode) {
    return state.enabled ? colorScheme.error : colorScheme.onSurfaceVariant;
  }

  if (button.action.type == ButtonActionType.toggleVirtualCamera ||
      button.action.type == ButtonActionType.toggleStudioMode) {
    return state.active ? Colors.cyan : colorScheme.onSurfaceVariant;
  }

  final fallback = _colorFromHex(button.activeColor) ?? colorScheme.primary;
  return state.active ? fallback : colorScheme.onSurfaceVariant;
}

class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.edit_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edit Mode: long press any button to open Button Editor. Actions are disabled.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          TextButton(
            onPressed: onExit,
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _VolunteerModeBanner extends StatelessWidget {
  const _VolunteerModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Volunteer Mode - Advanced controls disabled.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _CreateControllerPageInput {
  const _CreateControllerPageInput({required this.name});

  final String name;
}

class _CreateControllerPageSheet extends StatefulWidget {
  const _CreateControllerPageSheet();

  @override
  State<_CreateControllerPageSheet> createState() =>
      _CreateControllerPageSheetState();
}

class _CreateControllerPageSheetState
    extends State<_CreateControllerPageSheet> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 44,
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
                    hintText: 'e.g. Scenes',
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
                            _CreateControllerPageInput(
                              name: _nameController.text.trim(),
                            ),
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
