import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../domain/entities/audio_source.dart';
import '../../../../domain/entities/button_action.dart';
import '../../../../domain/entities/controller_button.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/entities/connection_status.dart';
import '../../../../domain/entities/obs_runtime_state.dart';
import '../../../../domain/entities/quick_control.dart';
import '../../../../domain/entities/recording_status.dart';
import '../../../../domain/entities/scene_item.dart';
import '../../../../domain/entities/scene_preview_mode.dart';
import '../../../../domain/entities/source_item.dart';
import '../../../../domain/entities/stream_status.dart';
import '../../../../domain/repositories/controller_repository.dart';
import '../../../../domain/usecases/execute_button_action_usecase.dart';
import '../../../../domain/usecases/load_controller_pages_usecase.dart';
import '../../../../domain/usecases/run_macro_usecase.dart';
import '../../../../shared/state/deck_button_runtime_state.dart';
import '../../../../shared/state/app_providers.dart';
import '../../../../shared/state/premium_controller.dart';
import '../models/controller_alert_banner.dart';
import '../../../../shared/volunteer/volunteer_mode_policy.dart';

enum ControllerInteractionMode { control, edit }

enum ControllerButtonInteractionOutcome {
  ignored,
  executed,
  holdRequired,
  blockedByPremium,
  blockedByVolunteerMode,
  selectedInEditMode,
  openEditor,
}

class ControllerScreenState {
  const ControllerScreenState({
    required this.pages,
    required this.currentPageIndex,
    required this.obsState,
    required this.interactionMode,
    this.banner,
    this.sceneThumbnails = const <String, String>{},
    this.pendingButtonIds = const <String>{},
    this.selectedButtonId,
    this.isLoading = false,
  });

  final List<ControllerPage> pages;
  final int currentPageIndex;
  final ObsRuntimeState obsState;
  final ControllerInteractionMode interactionMode;
  final ControllerAlertBanner? banner;
  final Map<String, String> sceneThumbnails;
  final Set<String> pendingButtonIds;
  final String? selectedButtonId;
  final bool isLoading;

  ControllerPage? get currentPage {
    if (pages.isEmpty) {
      return null;
    }
    if (currentPageIndex < 0 || currentPageIndex >= pages.length) {
      return pages.first;
    }
    return pages[currentPageIndex];
  }

  static const Object _bannerSentinel = Object();

  ControllerScreenState copyWith({
    List<ControllerPage>? pages,
    int? currentPageIndex,
    ObsRuntimeState? obsState,
    ControllerInteractionMode? interactionMode,
    Object? banner = _bannerSentinel,
    Map<String, String>? sceneThumbnails,
    Set<String>? pendingButtonIds,
    String? selectedButtonId,
    bool clearSelection = false,
    bool? isLoading,
  }) {
    return ControllerScreenState(
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      obsState: obsState ?? this.obsState,
      interactionMode: interactionMode ?? this.interactionMode,
      banner: identical(banner, _bannerSentinel)
          ? this.banner
          : banner as ControllerAlertBanner?,
      sceneThumbnails: sceneThumbnails ?? this.sceneThumbnails,
      pendingButtonIds: pendingButtonIds ?? this.pendingButtonIds,
      selectedButtonId:
          clearSelection ? null : (selectedButtonId ?? this.selectedButtonId),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ControllerController extends StateNotifier<ControllerScreenState> {
  ControllerController({
    required LoadControllerPagesUseCase loadPages,
    required ControllerRepository controllerRepository,
    required ExecuteButtonActionUseCase executeButtonAction,
    required RunMacroUseCase runMacro,
    required Ref ref,
  })  : _loadPages = loadPages,
        _controllerRepository = controllerRepository,
        _executeButtonAction = executeButtonAction,
        _runMacro = runMacro,
        _ref = ref,
        _scenePreviewMode = ref.read(scenePreviewModeProvider),
        _isPremiumUser = ref.read(premiumControllerProvider).isPremium,
        super(
          ControllerScreenState(
            pages: const <ControllerPage>[],
            currentPageIndex: 0,
            obsState: ref.read(obsRepositoryProvider).currentState(),
            interactionMode: ControllerInteractionMode.control,
            sceneThumbnails: _loadCachedSceneThumbnails(ref),
            selectedButtonId: null,
            isLoading: true,
          ),
        ) {
    _ref.listen<ScenePreviewMode>(scenePreviewModeProvider, (_, next) {
      _handleScenePreviewModeChanged(next);
    });
    _init();
  }

  final LoadControllerPagesUseCase _loadPages;
  final ControllerRepository _controllerRepository;
  final ExecuteButtonActionUseCase _executeButtonAction;
  final RunMacroUseCase _runMacro;
  final Ref _ref;
  ScenePreviewMode _scenePreviewMode;
  bool _isPremiumUser;

  StreamSubscription? _obsSub;
  Timer? _bannerAutoHideTimer;
  Timer? _scenePreviewRefreshTimer;
  Timer? _activeScenePreviewRefreshTimer;
  bool _isSyncingObsBackedPages = false;
  bool _isSyncingThumbnails = false;
  bool _isAppInForeground = true;
  String? _dismissedBannerKey;
  ObsRuntimeState? _previousObsState;

  Future<void> _init() async {
    _ref.listen<PremiumState>(premiumControllerProvider, (_, next) {
      if (_isPremiumUser == next.isPremium) return;
      _isPremiumUser = next.isPremium;
      _configureScenePreviewTimers();
      if (!_isPremiumUser && state.sceneThumbnails.isNotEmpty) {
        state = state.copyWith(sceneThumbnails: const <String, String>{});
        unawaited(_persistSceneThumbnailCache(const <String, String>{}));
      }

      if (state.obsState.connectionStatus == ConnectionStatus.connected) {
        unawaited(_syncObsBackedPages(state.obsState));
        if (_isPremiumUser) {
          unawaited(
            _refreshScenePreviewsForCurrentPage(
              scenes: state.obsState.scenes,
              refreshExisting: false,
            ),
          );
        }
      }
    });

    _obsSub = _ref.read(obsRepositoryProvider).watchState().listen((obsState) {
      _handleObsStateUpdated(obsState);
      if (obsState.connectionStatus == ConnectionStatus.connected) {
        unawaited(_syncObsBackedPages(obsState));
        unawaited(
          _refreshScenePreviewsForCurrentPage(
            scenes: obsState.scenes,
            refreshExisting: false,
          ),
        );
      }
    });

    final pages = await _loadPages();
    state = state.copyWith(pages: pages, isLoading: false);

    final obsState = _ref.read(obsRepositoryProvider).currentState();
    _previousObsState = obsState;
    _handleObsStateUpdated(obsState, triggerTransitionBanner: false);
    if (obsState.connectionStatus == ConnectionStatus.connected) {
      await _syncObsBackedPages(obsState);
      await _refreshScenePreviewsForCurrentPage(
        scenes: obsState.scenes,
        refreshExisting: false,
      );
    }
    _configureScenePreviewTimers();
  }

  Future<void> refreshPages() async {
    final pages = await _loadPages();
    var currentIndex = state.currentPageIndex;
    if (currentIndex >= pages.length) {
      currentIndex = pages.isEmpty ? 0 : pages.length - 1;
    }
    state = state.copyWith(
      pages: pages,
      currentPageIndex: currentIndex,
      clearSelection: true,
    );

    final obsState = state.obsState;
    if (obsState.connectionStatus == ConnectionStatus.connected) {
      await _syncObsBackedPages(obsState);
      await _refreshScenePreviewsForCurrentPage(
        scenes: obsState.scenes,
        refreshExisting: false,
      );
    }
  }

  void setPageIndex(int index) {
    if (index < 0 || index >= state.pages.length) return;
    state = state.copyWith(currentPageIndex: index);
    unawaited(
      _refreshScenePreviewsForCurrentPage(
        scenes: state.obsState.scenes,
        refreshExisting: false,
      ),
    );
  }

  Future<String?> createPage({String? name}) async {
    if (!_isPremiumUser &&
        _countFreePlanPages(state.pages) >= AppConstants.freePageLimit) {
      return null;
    }

    const pageColumns = AppConstants.defaultPageColumns;
    const pageRows = AppConstants.defaultPageRows;
    final pageId = 'page_${DateTime.now().microsecondsSinceEpoch}';

    final created = ControllerPage(
      id: pageId,
      name: (name == null || name.trim().isEmpty) ? 'New Page' : name.trim(),
      columns: pageColumns,
      rows: pageRows,
      buttons: const <ControllerButton>[],
      isDefault: state.pages.isEmpty,
    );

    final updated = <ControllerPage>[...state.pages, created];
    await _controllerRepository.savePages(updated);
    state = state.copyWith(
      pages: updated,
      currentPageIndex: updated.length - 1,
      clearSelection: true,
    );
    unawaited(
      _refreshScenePreviewsForCurrentPage(
        scenes: state.obsState.scenes,
        refreshExisting: false,
      ),
    );
    return pageId;
  }

  void toggleInteractionMode() {
    final nextMode = state.interactionMode == ControllerInteractionMode.control
        ? ControllerInteractionMode.edit
        : ControllerInteractionMode.control;
    setInteractionMode(nextMode);
  }

  void setInteractionMode(ControllerInteractionMode mode) {
    state = state.copyWith(
      interactionMode: mode,
      clearSelection: mode == ControllerInteractionMode.control,
    );
  }

  void selectButton(String buttonId) {
    state = state.copyWith(selectedButtonId: buttonId);
  }

  void dismissBanner() {
    final banner = state.banner;
    if (banner == null) return;
    _dismissedBannerKey = banner.key;
    _setBanner(null);
  }

  Future<void> refreshScenePreviewsManually() async {
    await _refreshScenePreviewsForCurrentPage(
      scenes: state.obsState.scenes,
      refreshExisting: true,
    );
    await _refreshActiveScenePreview(refreshExisting: true);
  }

  void setAppForeground(bool isForeground) {
    if (_isAppInForeground == isForeground) return;
    _isAppInForeground = isForeground;
    _configureScenePreviewTimers();

    if (isForeground && _scenePreviewMode != ScenePreviewMode.off) {
      unawaited(
        _refreshScenePreviewsForCurrentPage(
          scenes: state.obsState.scenes,
          refreshExisting: false,
        ),
      );
    }
  }

  DeckButtonRuntimeState resolveButtonState(ControllerButton button) {
    if (_isPremiumActionLocked(button.action)) {
      return const DeckButtonRuntimeState(
        enabled: true,
        active: false,
        pending: false,
        hasError: false,
      );
    }

    final pending = state.pendingButtonIds.contains(button.id);
    final active = _isActionActive(button.action);
    final enabled = _isActionEnabled(button.action);

    return DeckButtonRuntimeState(
      enabled: enabled,
      active: active,
      pending: pending,
      hasError: false,
    );
  }

  String? sceneThumbnailForButton(ControllerButton button) {
    if (!_isPremiumUser) return null;
    if (_scenePreviewMode == ScenePreviewMode.off) return null;
    if (button.action.type != ButtonActionType.switchScene) return null;
    final sceneName = _resolveSceneNameFromButtonTarget(button.action);
    if (sceneName == null) return null;
    return state.sceneThumbnails[sceneName];
  }

  void _handleScenePreviewModeChanged(ScenePreviewMode nextMode) {
    if (_scenePreviewMode == nextMode) return;
    _scenePreviewMode = nextMode;
    _configureScenePreviewTimers();

    if (nextMode != ScenePreviewMode.off) {
      unawaited(
        _refreshScenePreviewsForCurrentPage(
          scenes: state.obsState.scenes,
          refreshExisting: false,
        ),
      );
    }
  }

  void _configureScenePreviewTimers() {
    _scenePreviewRefreshTimer?.cancel();
    _activeScenePreviewRefreshTimer?.cancel();

    if (!_isPremiumUser ||
        !_isAppInForeground ||
        _scenePreviewMode != ScenePreviewMode.autoRefresh10s) {
      return;
    }

    _scenePreviewRefreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(
        _refreshScenePreviewsForCurrentPage(
          scenes: state.obsState.scenes,
          refreshExisting: true,
        ),
      );
    });

    _activeScenePreviewRefreshTimer =
        Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_refreshActiveScenePreview(refreshExisting: true));
    });
  }

  Future<void> _refreshScenePreviewsForCurrentPage({
    required List<SceneItem> scenes,
    required bool refreshExisting,
  }) async {
    if (!_isPremiumUser || _scenePreviewMode == ScenePreviewMode.off) return;

    final targets = _sceneTargetsForCurrentPage(scenes);
    if (targets.isEmpty) return;

    await _refreshSceneThumbnails(
      scenes,
      restrictToSceneNames: targets,
      refreshExisting: refreshExisting,
    );
  }

  Future<void> _refreshActiveScenePreview(
      {required bool refreshExisting}) async {
    if (!_isPremiumUser) return;
    if (_scenePreviewMode != ScenePreviewMode.autoRefresh10s) return;
    final activeScene = state.obsState.currentScene;
    if (activeScene == null || activeScene.trim().isEmpty) return;

    final scenes = state.obsState.scenes;
    await _refreshSceneThumbnails(
      scenes,
      restrictToSceneNames: <String>{activeScene},
      refreshExisting: refreshExisting,
    );
  }

  List<ControllerButton> quickControlButtons({
    required List<QuickControlId> controls,
  }) {
    final obs = state.obsState;
    final micTarget = _resolveMicAudioTarget(obs);
    final streamRunning = _isStreamRunning(obs.streamStatus);
    final recordingRunning = _isRecordingRunning(obs.recordingStatus);
    final virtualCameraRunning = obs.virtualCameraActive;
    final studioModeEnabled = obs.studioModeEnabled;
    final micSource = micTarget == null
        ? null
        : obs.audioSources
            .where((source) => source.id == micTarget)
            .firstOrNull;
    final micMuted = micSource?.isMuted ?? false;

    return controls
        .asMap()
        .entries
        .map(
          (entry) => switch (entry.value) {
            QuickControlId.muteMic => ControllerButton(
                id: 'quick_mic',
                label: micMuted ? 'Unmute Mic' : 'Mute Mic',
                icon: micMuted ? 'mic' : 'mic_off',
                activeColor: '#22C55E',
                inactiveColor: '#92400E',
                category: DeckButtonCategory.audio,
                action: ButtonAction(
                  type: micMuted
                      ? ButtonActionType.unmute
                      : ButtonActionType.mute,
                  targetId: micTarget,
                ),
                position: entry.key,
              ),
            QuickControlId.stream => ControllerButton(
                id: 'quick_stream',
                label: streamRunning ? 'Stop Stream' : 'Start Stream',
                icon: streamRunning ? 'stop_circle' : 'play_arrow',
                activeColor: '#EF4444',
                inactiveColor: '#166534',
                category: DeckButtonCategory.stream,
                action: ButtonAction(
                  type: streamRunning
                      ? ButtonActionType.stopStream
                      : ButtonActionType.startStream,
                ),
                position: entry.key,
                longPressTrigger: true,
              ),
            QuickControlId.recording => ControllerButton(
                id: 'quick_recording',
                label: recordingRunning ? 'Stop Recording' : 'Start Recording',
                icon: recordingRunning ? 'stop' : 'radio_button_checked',
                activeColor: '#EF4444',
                inactiveColor: '#166534',
                category: DeckButtonCategory.recording,
                action: ButtonAction(
                  type: recordingRunning
                      ? ButtonActionType.stopRecording
                      : ButtonActionType.startRecording,
                ),
                position: entry.key,
                longPressTrigger: true,
              ),
            QuickControlId.virtualCamera => ControllerButton(
                id: 'quick_virtual_cam',
                label: virtualCameraRunning
                    ? 'Stop Virtual Camera'
                    : 'Start Virtual Camera',
                icon: virtualCameraRunning ? 'videocam_off' : 'videocam',
                activeColor: '#EF4444',
                inactiveColor: '#0E7490',
                category: DeckButtonCategory.utility,
                action: ButtonAction(
                  type: virtualCameraRunning
                      ? ButtonActionType.stopVirtualCamera
                      : ButtonActionType.startVirtualCamera,
                ),
                position: entry.key,
              ),
            QuickControlId.studioMode => ControllerButton(
                id: 'quick_studio_mode',
                label: studioModeEnabled
                    ? 'Disable Studio Mode'
                    : 'Enable Studio Mode',
                icon: studioModeEnabled ? 'tune' : 'preview',
                activeColor: '#F59E0B',
                inactiveColor: '#1D4ED8',
                category: DeckButtonCategory.utility,
                action: ButtonAction(
                  type: studioModeEnabled
                      ? ButtonActionType.disableStudioMode
                      : ButtonActionType.enableStudioMode,
                ),
                position: entry.key,
              ),
          },
        )
        .toList(growable: false);
  }

  Future<ControllerButtonInteractionOutcome> onButtonTap(
    ControllerButton button,
  ) async {
    if (state.interactionMode == ControllerInteractionMode.edit) {
      selectButton(button.id);
      return ControllerButtonInteractionOutcome.selectedInEditMode;
    }

    if (_isPremiumActionLocked(button.action)) {
      return ControllerButtonInteractionOutcome.blockedByPremium;
    }

    if (_isVolunteerBlocked(button)) {
      return ControllerButtonInteractionOutcome.blockedByVolunteerMode;
    }

    final runtime = resolveButtonState(button);
    if (!runtime.enabled || runtime.pending) {
      return ControllerButtonInteractionOutcome.ignored;
    }
    if (button.longPressTrigger) {
      return ControllerButtonInteractionOutcome.holdRequired;
    }

    await _executeButton(button);
    return ControllerButtonInteractionOutcome.executed;
  }

  Future<ControllerButtonInteractionOutcome> onButtonLongPress(
    ControllerButton button,
  ) async {
    if (state.interactionMode == ControllerInteractionMode.edit) {
      selectButton(button.id);
      return ControllerButtonInteractionOutcome.openEditor;
    }

    if (_isPremiumActionLocked(button.action)) {
      return ControllerButtonInteractionOutcome.blockedByPremium;
    }

    if (_isVolunteerBlocked(button)) {
      return ControllerButtonInteractionOutcome.blockedByVolunteerMode;
    }

    final runtime = resolveButtonState(button);
    if (!runtime.enabled || runtime.pending) {
      return ControllerButtonInteractionOutcome.ignored;
    }
    if (!button.longPressTrigger) {
      return ControllerButtonInteractionOutcome.ignored;
    }

    await _executeButton(button);
    return ControllerButtonInteractionOutcome.executed;
  }

  Future<void> _executeButton(ControllerButton button) async {
    final pending = <String>{...state.pendingButtonIds, button.id};
    state = state.copyWith(pendingButtonIds: pending);

    try {
      if (button.action.type == ButtonActionType.runMacro) {
        final macroId = button.action.targetId;
        if (macroId != null) {
          await _runMacro(macroId);
        }
        return;
      }

      await _executeButtonAction(button.action);
    } catch (error) {
      _setBanner(
        ControllerAlertBanner(
          key: 'action_error_${button.id}',
          message: 'Request failed: ${_friendlyErrorMessage(error)}',
          level: ControllerAlertLevel.error,
          dismissible: true,
        ),
      );
    } finally {
      final nextPending = <String>{...state.pendingButtonIds}
        ..remove(button.id);
      state = state.copyWith(pendingButtonIds: nextPending);
    }
  }

  bool _isVolunteerBlocked(ControllerButton button) {
    if (!_ref.read(volunteerModeProvider)) return false;
    return VolunteerModePolicy.isRestrictedButtonAction(button.action.type);
  }

  void _handleObsStateUpdated(
    ObsRuntimeState obsState, {
    bool triggerTransitionBanner = true,
  }) {
    final previous = _previousObsState;
    _previousObsState = obsState;
    state = state.copyWith(obsState: obsState);

    _updateBannerForObs(
      previous: previous,
      current: obsState,
      triggerTransitionBanner: triggerTransitionBanner,
    );
  }

  void _updateBannerForObs({
    required ObsRuntimeState? previous,
    required ObsRuntimeState current,
    required bool triggerTransitionBanner,
  }) {
    final persistent = _persistentBannerFor(current);
    if (persistent != null) {
      if (persistent.key == _dismissedBannerKey) return;
      _setBanner(persistent);
      return;
    }

    _dismissedBannerKey = null;

    if (!triggerTransitionBanner || previous == null) {
      if (state.banner != null &&
          state.banner!.level != ControllerAlertLevel.success) {
        _setBanner(null);
      }
      return;
    }

    final transitionBanner =
        _transitionBannerFor(previous: previous, current: current);
    if (transitionBanner != null) {
      _setBanner(transitionBanner);
      return;
    }

    if (state.banner != null &&
        state.banner!.level != ControllerAlertLevel.success) {
      _setBanner(null);
    }
  }

  ControllerAlertBanner? _persistentBannerFor(ObsRuntimeState obs) {
    switch (obs.connectionStatus) {
      case ConnectionStatus.disconnected:
        return const ControllerAlertBanner(
          key: 'conn_disconnected',
          message: 'OBS disconnected.',
          level: ControllerAlertLevel.error,
          dismissible: true,
        );
      case ConnectionStatus.connecting:
        return const ControllerAlertBanner(
          key: 'conn_connecting',
          message: 'Connecting to OBS...',
          level: ControllerAlertLevel.warning,
          dismissible: true,
        );
      case ConnectionStatus.reconnecting:
        return const ControllerAlertBanner(
          key: 'conn_reconnecting',
          message: 'Connection lost. Reconnecting...',
          level: ControllerAlertLevel.warning,
          dismissible: true,
        );
      case ConnectionStatus.wrongPassword:
        return const ControllerAlertBanner(
          key: 'conn_auth_failed',
          message: 'OBS authentication failed.',
          level: ControllerAlertLevel.error,
          dismissible: true,
        );
      case ConnectionStatus.notFound:
        return const ControllerAlertBanner(
          key: 'conn_not_found',
          message: 'Could not reach OBS host/port.',
          level: ControllerAlertLevel.error,
          dismissible: true,
        );
      case ConnectionStatus.error:
        return ControllerAlertBanner(
          key: 'conn_error',
          message: obs.lastError ?? 'Unexpected OBS error.',
          level: ControllerAlertLevel.error,
          dismissible: true,
        );
      case ConnectionStatus.connected:
        break;
    }

    if (obs.streamStatus == StreamStatus.error) {
      return ControllerAlertBanner(
        key: 'stream_error',
        message: obs.lastError ?? 'Stream error detected.',
        level: ControllerAlertLevel.error,
        dismissible: true,
      );
    }

    if (obs.recordingStatus == RecordingStatus.error) {
      return ControllerAlertBanner(
        key: 'record_error',
        message: obs.lastError ?? 'Recording error detected.',
        level: ControllerAlertLevel.error,
        dismissible: true,
      );
    }

    final healthWarning = _streamHealthWarning(obs);
    if (healthWarning != null) return healthWarning;

    return null;
  }

  ControllerAlertBanner? _streamHealthWarning(ObsRuntimeState obs) {
    if (!_isPremiumUser) return null;
    if (obs.streamStatus != StreamStatus.live) return null;

    if (obs.outputReconnecting) {
      return const ControllerAlertBanner(
        key: 'stream_reconnecting',
        message: 'Network unstable: OBS output reconnecting.',
        level: ControllerAlertLevel.warning,
        dismissible: true,
      );
    }

    if (obs.outputCongestion >= 0.15) {
      final pct = (obs.outputCongestion * 100).toStringAsFixed(1);
      return ControllerAlertBanner(
        key: 'stream_congestion',
        message: 'High congestion detected ($pct%).',
        level: ControllerAlertLevel.warning,
        dismissible: true,
      );
    }

    if (obs.outputSkippedFramesPercent >= 1.0 ||
        obs.droppedFramesPercent >= 1.0) {
      final skipped = obs.outputSkippedFramesPercent.toStringAsFixed(1);
      return ControllerAlertBanner(
        key: 'stream_skipped_frames',
        message: 'Dropped/skipped frames rising ($skipped%).',
        level: ControllerAlertLevel.warning,
        dismissible: true,
      );
    }

    return null;
  }

  ControllerAlertBanner? _transitionBannerFor({
    required ObsRuntimeState previous,
    required ObsRuntimeState current,
  }) {
    if (previous.connectionStatus != ConnectionStatus.connected &&
        current.connectionStatus == ConnectionStatus.connected) {
      return const ControllerAlertBanner(
        key: 'conn_recovered',
        message: 'Connected to OBS.',
        level: ControllerAlertLevel.success,
        dismissible: false,
        autoHideAfter: Duration(seconds: 2),
      );
    }

    final prevHealthWarning = _streamHealthWarning(previous);
    final currentHealthWarning = _streamHealthWarning(current);
    if (prevHealthWarning != null && currentHealthWarning == null) {
      return const ControllerAlertBanner(
        key: 'stream_health_recovered',
        message: 'Stream health recovered.',
        level: ControllerAlertLevel.success,
        dismissible: false,
        autoHideAfter: Duration(seconds: 2),
      );
    }

    if (previous.streamStatus != StreamStatus.live &&
        current.streamStatus == StreamStatus.live) {
      return const ControllerAlertBanner(
        key: 'stream_started',
        message: 'Stream started.',
        level: ControllerAlertLevel.success,
        dismissible: false,
        autoHideAfter: Duration(seconds: 2),
      );
    }

    if (previous.streamStatus == StreamStatus.live &&
        current.streamStatus == StreamStatus.offline) {
      return const ControllerAlertBanner(
        key: 'stream_stopped',
        message: 'Stream stopped.',
        level: ControllerAlertLevel.warning,
        dismissible: false,
        autoHideAfter: Duration(seconds: 2),
      );
    }

    final previousRecordingActive =
        previous.recordingStatus == RecordingStatus.recording ||
            previous.recordingStatus == RecordingStatus.paused;
    final currentRecordingActive =
        current.recordingStatus == RecordingStatus.recording ||
            current.recordingStatus == RecordingStatus.paused;
    if (!previousRecordingActive && currentRecordingActive) {
      return const ControllerAlertBanner(
        key: 'recording_started',
        message: 'Recording started.',
        level: ControllerAlertLevel.success,
        dismissible: false,
        autoHideAfter: Duration(seconds: 2),
      );
    }

    return null;
  }

  void _setBanner(ControllerAlertBanner? banner) {
    if (state.banner?.key == banner?.key &&
        state.banner?.message == banner?.message &&
        state.banner?.level == banner?.level) {
      return;
    }

    _bannerAutoHideTimer?.cancel();
    state = state.copyWith(banner: banner);

    final autoHideAfter = banner?.autoHideAfter;
    if (autoHideAfter == null) return;
    _bannerAutoHideTimer = Timer(autoHideAfter, () {
      if (state.banner?.key == banner?.key) {
        state = state.copyWith(banner: null);
      }
    });
  }

  Future<void> _syncObsBackedPages(ObsRuntimeState obsState) async {
    if (_isSyncingObsBackedPages) return;

    _isSyncingObsBackedPages = true;
    try {
      final pages = <ControllerPage>[...state.pages];
      var changed = false;

      changed = _upsertScenesPage(pages, obsState) || changed;
      changed = _upsertEmergencyPage(pages, obsState) || changed;

      if (!changed) return;

      state = state.copyWith(pages: pages);
      await _controllerRepository.savePages(pages);
    } finally {
      _isSyncingObsBackedPages = false;
    }
  }

  bool _upsertScenesPage(List<ControllerPage> pages, ObsRuntimeState obsState) {
    if (obsState.scenes.isEmpty) return false;

    if (pages.isEmpty) {
      pages.add(
        const ControllerPage(
          id: 'scenes',
          name: 'Scenes',
          columns: AppConstants.defaultPageColumns,
          rows: AppConstants.defaultPageRows,
          buttons: <ControllerButton>[],
          isDefault: true,
        ),
      );
    }

    var scenesPageIndex = pages.indexWhere(_isScenesPage);
    if (scenesPageIndex < 0) {
      final shouldBeDefault = pages.every((page) => !page.isDefault);
      pages.insert(
        0,
        ControllerPage(
          id: 'scenes',
          name: 'Scenes',
          columns: AppConstants.defaultPageColumns,
          rows: AppConstants.defaultPageRows,
          buttons: const <ControllerButton>[],
          isDefault: shouldBeDefault,
        ),
      );
      scenesPageIndex = 0;
    }

    final scenesPage = pages[scenesPageIndex];
    final nextButtons = _buildObsSceneButtons(obsState.scenes);
    final safeColumns = scenesPage.columns <= 0 ? 1 : scenesPage.columns;
    final computedRows = ((nextButtons.length + safeColumns - 1) / safeColumns)
        .ceil()
        .clamp(1, 99);
    final nextRows = computedRows < AppConstants.defaultPageRows
        ? AppConstants.defaultPageRows
        : computedRows;

    if (_sameSceneButtons(scenesPage.buttons, nextButtons) &&
        scenesPage.rows == nextRows) {
      return false;
    }

    pages[scenesPageIndex] = scenesPage.copyWith(
      buttons: nextButtons,
      rows: nextRows,
    );
    return true;
  }

  bool _upsertEmergencyPage(
    List<ControllerPage> pages,
    ObsRuntimeState obsState,
  ) {
    var emergencyIndex = pages.indexWhere(_isEmergencyPage);
    if (emergencyIndex < 0) {
      pages.add(
        const ControllerPage(
          id: 'emergency',
          name: 'Emergency',
          columns: 4,
          rows: 3,
          buttons: <ControllerButton>[],
          isDefault: false,
        ),
      );
      emergencyIndex = pages.length - 1;
    }

    final emergencyPage = pages[emergencyIndex];
    final nextButtons = _buildEmergencyButtons(obsState);
    final nextRows = ((nextButtons.length + 3) / 4).ceil().clamp(3, 99);

    if (_sameEmergencyButtons(emergencyPage.buttons, nextButtons) &&
        emergencyPage.columns == 4 &&
        emergencyPage.rows == nextRows) {
      return false;
    }

    pages[emergencyIndex] = emergencyPage.copyWith(
      columns: 4,
      rows: nextRows,
      buttons: nextButtons,
    );
    return true;
  }

  bool _isScenesPage(ControllerPage page) {
    final normalizedId = page.id.trim().toLowerCase();
    final normalizedName = page.name.trim().toLowerCase();
    return normalizedId == 'scenes' || normalizedName == 'scenes';
  }

  bool _isEmergencyPage(ControllerPage page) {
    final normalizedId = page.id.trim().toLowerCase();
    final normalizedName = page.name.trim().toLowerCase();
    return normalizedId == 'emergency' || normalizedName == 'emergency';
  }

  int _countFreePlanPages(List<ControllerPage> pages) {
    return pages.where((page) => !_isEmergencyPage(page)).length;
  }

  List<ControllerButton> _buildObsSceneButtons(List<SceneItem> scenes) {
    final maxScenes = _isPremiumUser
        ? scenes.length
        : AppConstants.freeSceneButtonLimit.clamp(0, scenes.length);
    final visibleScenes = scenes.take(maxScenes).toList(growable: false);

    final next = visibleScenes.asMap().entries.map((entry) {
      final position = entry.key;
      final scene = entry.value;
      return ControllerButton(
        id: 'obs_scene_${position}_${_sceneButtonIdPart(scene.id)}',
        label: scene.name,
        icon: 'movie',
        activeColor: '#137FEC',
        inactiveColor: '#64748B',
        category: DeckButtonCategory.scene,
        action: ButtonAction(
          type: ButtonActionType.switchScene,
          targetId: scene.id,
        ),
        position: position,
      );
    }).toList(growable: true);

    if (!_isPremiumUser && scenes.length > AppConstants.freeSceneButtonLimit) {
      next.add(
        ControllerButton(
          id: 'premium_unlock_scenes',
          label: 'Unlock More Scenes',
          icon: 'lock',
          activeColor: '#EAB308',
          inactiveColor: '#A16207',
          category: DeckButtonCategory.utility,
          action: const ButtonAction(
            type: ButtonActionType.runMacro,
            metadata: <String, dynamic>{
              'premiumFeature': 'unlimitedScenes',
            },
          ),
          position: next.length,
        ),
      );
    }

    return next;
  }

  String _sceneButtonIdPart(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  bool _sameSceneButtons(
    List<ControllerButton> current,
    List<ControllerButton> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      final existing = current[i];
      final candidate = next[i];
      final existingPremiumLock = existing.action.metadata['premiumFeature'];
      final candidatePremiumLock = candidate.action.metadata['premiumFeature'];
      if (existingPremiumLock != null || candidatePremiumLock != null) {
        if (existingPremiumLock != candidatePremiumLock) return false;
        if (existing.label != candidate.label) return false;
        if (existing.position != candidate.position) return false;
        continue;
      }
      if (existing.action.type != ButtonActionType.switchScene ||
          candidate.action.type != ButtonActionType.switchScene) {
        return false;
      }
      if (existing.action.targetId != candidate.action.targetId) return false;
      if (existing.label != candidate.label) return false;
      if (existing.position != candidate.position) return false;
    }
    return true;
  }

  List<ControllerButton> _buildEmergencyButtons(ObsRuntimeState obsState) {
    if (!_isPremiumUser) {
      return _buildLockedEmergencyButtons();
    }

    final safeSceneTarget = _resolveSafeSceneTarget(obsState);
    final brbSceneTarget = _resolveBrbSceneTarget(obsState);
    final micTarget = _resolveMicAudioTarget(obsState);
    final desktopTarget = _resolveDesktopAudioTarget(obsState);
    final cameraTarget = _resolveCameraSourceTarget(obsState);

    return <ControllerButton>[
      ControllerButton(
        id: 'emer_safe_scene',
        label: 'Safe Scene',
        icon: 'tv_off',
        activeColor: '#137FEC',
        inactiveColor: '#1E3A8A',
        category: DeckButtonCategory.utility,
        action: ButtonAction(
          type: ButtonActionType.switchScene,
          targetId: safeSceneTarget,
        ),
        position: 0,
      ),
      ControllerButton(
        id: 'emer_brb_scene',
        label: 'BRB Scene',
        icon: 'airplay',
        activeColor: '#137FEC',
        inactiveColor: '#1E3A8A',
        category: DeckButtonCategory.utility,
        action: ButtonAction(
          type: ButtonActionType.switchScene,
          targetId: brbSceneTarget ?? safeSceneTarget,
        ),
        position: 1,
      ),
      ControllerButton(
        id: 'emer_mute_mic',
        label: 'Mute Mic',
        icon: 'mic_off',
        activeColor: '#F59E0B',
        inactiveColor: '#92400E',
        category: DeckButtonCategory.audio,
        action: ButtonAction(
          type: ButtonActionType.mute,
          targetId: micTarget,
        ),
        position: 2,
      ),
      const ControllerButton(
        id: 'emer_mute_all',
        label: 'Mute All',
        icon: 'volume_off',
        activeColor: '#F59E0B',
        inactiveColor: '#92400E',
        category: DeckButtonCategory.audio,
        action: ButtonAction(
          type: ButtonActionType.toggleMute,
          targetId: 'all_audio',
          metadata: <String, dynamic>{'all': true},
        ),
        position: 3,
      ),
      ControllerButton(
        id: 'emer_hide_camera',
        label: 'Hide Camera',
        icon: 'videocam_off',
        activeColor: '#14B8A6',
        inactiveColor: '#0F766E',
        category: DeckButtonCategory.source,
        action: ButtonAction(
          type: ButtonActionType.toggleSourceVisibility,
          targetId: cameraTarget,
        ),
        position: 4,
      ),
      const ControllerButton(
        id: 'emer_hide_overlays',
        label: 'Hide Overlays',
        icon: 'layers_clear',
        activeColor: '#14B8A6',
        inactiveColor: '#0F766E',
        category: DeckButtonCategory.source,
        action: ButtonAction(
          type: ButtonActionType.hideSource,
          targetId: 'overlay_group',
        ),
        position: 5,
      ),
      ControllerButton(
        id: 'emer_mute_desktop',
        label: 'Mute Desktop',
        icon: 'volume_mute',
        activeColor: '#F59E0B',
        inactiveColor: '#92400E',
        category: DeckButtonCategory.audio,
        action: ButtonAction(
          type: ButtonActionType.mute,
          targetId: desktopTarget,
        ),
        position: 6,
      ),
      const ControllerButton(
        id: 'emer_stop_stream',
        label: 'STOP STREAM',
        icon: 'stop_circle',
        activeColor: '#EF4444',
        inactiveColor: '#7F1D1D',
        category: DeckButtonCategory.stream,
        action: ButtonAction(type: ButtonActionType.stopStream),
        position: 7,
        longPressTrigger: true,
      ),
      const ControllerButton(
        id: 'emer_stop_recording',
        label: 'Stop Recording',
        icon: 'stop',
        activeColor: '#EF4444',
        inactiveColor: '#7F1D1D',
        category: DeckButtonCategory.recording,
        action: ButtonAction(type: ButtonActionType.stopRecording),
        position: 8,
        longPressTrigger: true,
      ),
      const ControllerButton(
        id: 'emer_restart_stream',
        label: 'Restart Stream',
        icon: 'autorenew',
        activeColor: '#EF4444',
        inactiveColor: '#7F1D1D',
        category: DeckButtonCategory.macro,
        action: ButtonAction(
          type: ButtonActionType.runMacro,
          targetId: 'macro_restart_stream',
        ),
        position: 9,
        longPressTrigger: true,
      ),
      const ControllerButton(
        id: 'emer_reset',
        label: 'Emergency Reset',
        icon: 'restart_alt',
        activeColor: '#EF4444',
        inactiveColor: '#7F1D1D',
        category: DeckButtonCategory.macro,
        action: ButtonAction(
          type: ButtonActionType.runMacro,
          targetId: 'macro_emergency_reset',
        ),
        position: 10,
        longPressTrigger: true,
      ),
    ];
  }

  List<ControllerButton> _buildLockedEmergencyButtons() {
    const labels = <(String, String)>[
      ('Safe Scene', 'tv_off'),
      ('BRB Scene', 'airplay'),
      ('Mute Mic', 'mic_off'),
      ('Mute All', 'volume_off'),
      ('Hide Camera', 'videocam_off'),
      ('Hide Overlays', 'layers_clear'),
      ('Mute Desktop', 'volume_mute'),
      ('Stop Stream', 'stop_circle'),
      ('Stop Recording', 'stop'),
      ('Restart Stream', 'autorenew'),
    ];

    return labels.asMap().entries.map((entry) {
      final index = entry.key;
      final (label, icon) = entry.value;
      return ControllerButton(
        id: 'emer_lock_${index + 1}',
        label: label,
        icon: icon,
        activeColor: '#EAB308',
        inactiveColor: '#A16207',
        category: DeckButtonCategory.utility,
        action: const ButtonAction(
          type: ButtonActionType.runMacro,
          metadata: <String, dynamic>{
            'premiumFeature': 'emergencyPage',
          },
        ),
        position: index,
      );
    }).toList(growable: false);
  }

  String? _resolveSafeSceneTarget(ObsRuntimeState obsState) {
    if (obsState.scenes.isEmpty) return null;

    final keywords = <String>['safe', 'brb', 'break', 'intermission'];
    final candidate = obsState.scenes.where((scene) {
      final normalized = _normalizeToken(scene.name);
      return keywords.any(normalized.contains);
    }).firstOrNull;
    return candidate?.id ?? obsState.scenes.first.id;
  }

  String? _resolveBrbSceneTarget(ObsRuntimeState obsState) {
    if (obsState.scenes.isEmpty) return null;

    final keywords = <String>['brb', 'break', 'intermission', 'berightback'];
    final candidate = obsState.scenes.where((scene) {
      final normalized = _normalizeToken(scene.name);
      return keywords.any(normalized.contains);
    }).firstOrNull;
    return candidate?.id;
  }

  String? _resolveMicAudioTarget(ObsRuntimeState obsState) {
    if (obsState.audioSources.isEmpty) return null;

    final keywords = <String>['mic', 'microphone', 'xlr', 'voice'];
    final candidate = obsState.audioSources.where((source) {
      final normalized = _normalizeToken(source.name);
      return keywords.any(normalized.contains);
    }).firstOrNull;
    return candidate?.id ?? obsState.audioSources.first.id;
  }

  String? _resolveDesktopAudioTarget(ObsRuntimeState obsState) {
    if (obsState.audioSources.isEmpty) return null;

    final keywords = <String>['desktop', 'system', 'game', 'speaker', 'output'];
    final candidate = obsState.audioSources.where((source) {
      final normalized = _normalizeToken(source.name);
      return keywords.any(normalized.contains);
    }).firstOrNull;
    if (candidate != null) return candidate.id;
    if (obsState.audioSources.length > 1) return obsState.audioSources[1].id;
    return obsState.audioSources.first.id;
  }

  String? _resolveCameraSourceTarget(ObsRuntimeState obsState) {
    if (obsState.sources.isEmpty) return null;

    final keywords = <String>['camera', 'cam', 'webcam', 'video'];
    final candidate = obsState.sources.where((source) {
      final normalized = _normalizeToken(source.name);
      return keywords.any(normalized.contains);
    }).firstOrNull;
    return candidate?.id;
  }

  String _normalizeToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  bool _sameEmergencyButtons(
    List<ControllerButton> current,
    List<ControllerButton> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = next[i];
      if (a.id != b.id) return false;
      if (a.label != b.label) return false;
      if (a.action.type != b.action.type) return false;
      if (a.action.targetId != b.action.targetId) return false;
      if (a.action.targetName != b.action.targetName) return false;
      if (a.longPressTrigger != b.longPressTrigger) return false;
    }
    return true;
  }

  bool isButtonActive(ControllerButton button) {
    return _isActionActive(button.action);
  }

  bool _isActionEnabled(ButtonAction action) {
    if (_isPremiumActionLocked(action)) {
      return true;
    }

    final obs = state.obsState;
    if (obs.connectionStatus != ConnectionStatus.connected) {
      return false;
    }

    final streamActive = _isStreamRunning(obs.streamStatus);
    final recordingActive = _isRecordingRunning(obs.recordingStatus);

    switch (action.type) {
      case ButtonActionType.switchScene:
        final targetScene = _resolveSceneNameFromButtonTarget(action);
        return targetScene != null && targetScene != obs.currentScene;
      case ButtonActionType.setPreviewScene:
        final targetScene = _resolveSceneNameFromButtonTarget(action);
        return obs.studioModeEnabled &&
            targetScene != null &&
            targetScene != obs.previewScene;
      case ButtonActionType.mute:
        final matches = _matchingAudioSources(action);
        return matches.any((source) => !source.isMuted);
      case ButtonActionType.unmute:
        final matches = _matchingAudioSources(action);
        return matches.any((source) => source.isMuted);
      case ButtonActionType.toggleMute:
        return _matchingAudioSources(action).isNotEmpty;
      case ButtonActionType.showSource:
        final matches = _matchingSources(action);
        return matches.any((source) => !source.isVisible);
      case ButtonActionType.hideSource:
        final matches = _matchingSources(action);
        return matches.any((source) => source.isVisible);
      case ButtonActionType.toggleSourceVisibility:
        return _matchingSources(action).isNotEmpty;
      case ButtonActionType.startStream:
        return !streamActive && obs.streamStatus != StreamStatus.stopping;
      case ButtonActionType.stopStream:
        return obs.streamStatus == StreamStatus.live;
      case ButtonActionType.toggleStream:
        return obs.streamStatus != StreamStatus.starting &&
            obs.streamStatus != StreamStatus.stopping;
      case ButtonActionType.startRecording:
        return !recordingActive &&
            obs.recordingStatus != RecordingStatus.stopping;
      case ButtonActionType.stopRecording:
        return obs.recordingStatus == RecordingStatus.recording ||
            obs.recordingStatus == RecordingStatus.paused;
      case ButtonActionType.pauseRecording:
        return obs.recordingStatus == RecordingStatus.recording;
      case ButtonActionType.resumeRecording:
        return obs.recordingStatus == RecordingStatus.paused;
      case ButtonActionType.toggleRecording:
        return obs.recordingStatus != RecordingStatus.starting &&
            obs.recordingStatus != RecordingStatus.stopping;
      case ButtonActionType.startVirtualCamera:
        return !obs.virtualCameraActive;
      case ButtonActionType.stopVirtualCamera:
        return obs.virtualCameraActive;
      case ButtonActionType.toggleVirtualCamera:
        return true;
      case ButtonActionType.enableStudioMode:
        return !obs.studioModeEnabled;
      case ButtonActionType.disableStudioMode:
        return obs.studioModeEnabled;
      case ButtonActionType.toggleStudioMode:
        return true;
      case ButtonActionType.runMacro:
        return true;
    }
  }

  bool _isActionActive(ButtonAction action) {
    if (_isPremiumActionLocked(action)) return false;

    final obs = state.obsState;
    final streamActive = _isStreamRunning(obs.streamStatus);
    final recordingActive = _isRecordingRunning(obs.recordingStatus);

    switch (action.type) {
      case ButtonActionType.switchScene:
        return _matchesScene(
          obs: obs,
          activeSceneName: obs.currentScene,
          targetId: action.targetId,
          targetName: action.targetName,
        );
      case ButtonActionType.setPreviewScene:
        return _matchesScene(
          obs: obs,
          activeSceneName: obs.previewScene,
          targetId: action.targetId,
          targetName: action.targetName,
        );
      case ButtonActionType.mute:
        final mutedTargets = _matchingAudioSources(action);
        return mutedTargets.isNotEmpty &&
            mutedTargets.every((source) => source.isMuted);
      case ButtonActionType.unmute:
        final unmutedTargets = _matchingAudioSources(action);
        return unmutedTargets.isNotEmpty &&
            unmutedTargets.every((source) => !source.isMuted);
      case ButtonActionType.toggleMute:
        final toggledTargets = _matchingAudioSources(action);
        return toggledTargets.isNotEmpty &&
            toggledTargets.every((source) => source.isMuted);
      case ButtonActionType.showSource:
        final shownTargets = _matchingSources(action);
        return shownTargets.isNotEmpty &&
            shownTargets.every((source) => source.isVisible);
      case ButtonActionType.hideSource:
      case ButtonActionType.toggleSourceVisibility:
        final hiddenTargets = _matchingSources(action);
        return hiddenTargets.isNotEmpty &&
            hiddenTargets.every((source) => !source.isVisible);
      case ButtonActionType.startStream:
        return !streamActive;
      case ButtonActionType.stopStream:
        return streamActive;
      case ButtonActionType.toggleStream:
        return streamActive;
      case ButtonActionType.startRecording:
        return !recordingActive;
      case ButtonActionType.stopRecording:
        return recordingActive;
      case ButtonActionType.toggleRecording:
        return recordingActive;
      case ButtonActionType.pauseRecording:
        return obs.recordingStatus == RecordingStatus.paused;
      case ButtonActionType.resumeRecording:
        return obs.recordingStatus == RecordingStatus.recording;
      case ButtonActionType.startVirtualCamera:
        return !obs.virtualCameraActive;
      case ButtonActionType.stopVirtualCamera:
      case ButtonActionType.toggleVirtualCamera:
        return obs.virtualCameraActive;
      case ButtonActionType.enableStudioMode:
        return !obs.studioModeEnabled;
      case ButtonActionType.disableStudioMode:
      case ButtonActionType.toggleStudioMode:
        return obs.studioModeEnabled;
      case ButtonActionType.runMacro:
        return false;
    }
  }

  String? _resolveSceneNameFromButtonTarget(ButtonAction action) {
    final obs = state.obsState;
    if (action.targetId != null) {
      final byId = obs.scenes
          .where((scene) => scene.id == action.targetId)
          .map((scene) => scene.name)
          .firstOrNull;
      if (byId != null) return byId;
      final byName = obs.scenes
          .where((scene) => scene.name == action.targetId)
          .map((scene) => scene.name)
          .firstOrNull;
      if (byName != null) return byName;
    }

    if (action.targetName != null) {
      final byName = obs.scenes
          .where((scene) => scene.name == action.targetName)
          .map((scene) => scene.name)
          .firstOrNull;
      if (byName != null) return byName;
    }

    if (action.targetId != null && action.targetId!.isNotEmpty) {
      return action.targetId;
    }
    if (action.targetName != null && action.targetName!.isNotEmpty) {
      return action.targetName;
    }
    return null;
  }

  List<AudioSource> _matchingAudioSources(ButtonAction action) {
    final obs = state.obsState;
    if (obs.audioSources.isEmpty) return const <AudioSource>[];

    if (action.metadata['all'] == true ||
        _normalizeToken(action.targetId ?? action.targetName ?? '') ==
            'allaudio') {
      return obs.audioSources;
    }

    final targetId = action.targetId;
    final targetName = action.targetName;
    return obs.audioSources.where((source) {
      return (targetId != null &&
              (source.id == targetId || source.name == targetId)) ||
          (targetName != null &&
              (source.id == targetName || source.name == targetName));
    }).toList();
  }

  List<SourceItem> _matchingSources(ButtonAction action) {
    final obs = state.obsState;
    if (obs.sources.isEmpty) return const <SourceItem>[];

    final targetId = action.targetId;
    final targetName = action.targetName;
    if (_isOverlayTarget(targetId) || _isOverlayTarget(targetName)) {
      return _resolveOverlaySources(obs);
    }

    return obs.sources.where((source) {
      return (targetId != null &&
              (source.id == targetId || source.name == targetId)) ||
          (targetName != null &&
              (source.id == targetName || source.name == targetName));
    }).toList();
  }

  bool _isOverlayTarget(String? value) {
    if (value == null || value.isEmpty) return false;
    final normalized = _normalizeToken(value);
    return normalized == 'overlaygroup' ||
        normalized == 'overlays' ||
        normalized == 'hideoverlays';
  }

  List<SourceItem> _resolveOverlaySources(ObsRuntimeState obs) {
    const overlayKeywords = <String>[
      'overlay',
      'chat',
      'alert',
      'browser',
      'widget',
      'lowerthird',
    ];
    return obs.sources.where((source) {
      final normalized = _normalizeToken(source.name);
      return overlayKeywords.any(normalized.contains);
    }).toList();
  }

  bool _isStreamRunning(StreamStatus status) {
    return status == StreamStatus.live || status == StreamStatus.starting;
  }

  bool _isRecordingRunning(RecordingStatus status) {
    return status == RecordingStatus.recording ||
        status == RecordingStatus.paused ||
        status == RecordingStatus.starting;
  }

  Set<String> _sceneTargetsForCurrentPage(List<SceneItem> scenes) {
    final page = state.currentPage;
    if (page == null) return const <String>{};

    final targets = <String>{};
    for (final button in page.buttons) {
      final action = button.action;
      if (action.type != ButtonActionType.switchScene &&
          action.type != ButtonActionType.setPreviewScene) {
        continue;
      }

      final targetToken = action.targetId ?? action.targetName;
      if (targetToken == null || targetToken.trim().isEmpty) continue;
      final resolved = _resolveSceneNameToken(targetToken, scenes);
      if (resolved != null) {
        targets.add(resolved);
      }
    }

    return targets;
  }

  String? _resolveSceneNameToken(String targetToken, List<SceneItem> scenes) {
    final token = targetToken.trim();
    if (token.isEmpty) return null;
    final scene = scenes
        .where((entry) => entry.id == token || entry.name == token)
        .firstOrNull;
    if (scene != null) return scene.name;
    return token;
  }

  Future<void> _refreshSceneThumbnails(
    List<SceneItem> scenes, {
    required bool refreshExisting,
    Set<String>? restrictToSceneNames,
  }) async {
    if (!_isPremiumUser || _scenePreviewMode == ScenePreviewMode.off) return;
    if (_isSyncingThumbnails) return;
    if (!_isAppInForeground) return;
    if (state.obsState.connectionStatus != ConnectionStatus.connected) return;

    if (scenes.isEmpty) {
      if (state.sceneThumbnails.isNotEmpty) {
        state = state.copyWith(sceneThumbnails: const <String, String>{});
        unawaited(_persistSceneThumbnailCache(const <String, String>{}));
      }
      return;
    }

    final expectedNames = scenes
        .map((scene) => scene.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final currentThumbs = state.sceneThumbnails;
    final staleKeys = currentThumbs.keys
        .where((name) => !expectedNames.contains(name))
        .toList(growable: false);

    final rawTargets = (restrictToSceneNames ?? expectedNames)
        .where((name) => name.trim().isNotEmpty);
    final targetNames = rawTargets
        .map((target) => _resolveSceneNameToken(target, scenes))
        .whereType<String>()
        .toSet();
    if (targetNames.isEmpty && staleKeys.isEmpty) return;

    final fetchQueue = refreshExisting
        ? targetNames.toList(growable: false)
        : targetNames
            .where((name) => !currentThumbs.containsKey(name))
            .toList(growable: false);
    if (fetchQueue.isEmpty && staleKeys.isEmpty) return;

    _isSyncingThumbnails = true;
    try {
      final next = <String, String>{...currentThumbs};
      for (final stale in staleKeys) {
        next.remove(stale);
      }

      for (final sceneName in fetchQueue) {
        final image =
            await _ref.read(obsRepositoryProvider).fetchSceneThumbnail(
                  sceneName,
                  width: 320,
                  height: 180,
                  quality: 24,
                );
        if (image != null && image.isNotEmpty) {
          next[sceneName] = image;
        }
      }

      if (!_stringMapEquals(currentThumbs, next)) {
        state = state.copyWith(sceneThumbnails: next);
        unawaited(_persistSceneThumbnailCache(next));
      }
    } finally {
      _isSyncingThumbnails = false;
    }
  }

  bool _isPremiumActionLocked(ButtonAction action) {
    if (_isPremiumUser) return false;

    if (action.metadata['premiumFeature'] != null) {
      return true;
    }

    if (action.type == ButtonActionType.runMacro) {
      return true;
    }

    return false;
  }

  bool _stringMapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _persistSceneThumbnailCache(
    Map<String, String> thumbnails,
  ) async {
    try {
      await _ref
          .read(localStorageServiceProvider)
          .setJson(StorageKeys.sceneThumbnailCache, thumbnails);
    } catch (_) {
      // Ignore local cache persistence failures.
    }
  }

  static Map<String, String> _loadCachedSceneThumbnails(Ref ref) {
    final raw = ref
        .read(localStorageServiceProvider)
        .getJsonMap(StorageKeys.sceneThumbnailCache);
    if (raw == null || raw.isEmpty) return const <String, String>{};

    final parsed = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (key.isEmpty || value is! String || value.isEmpty) {
        continue;
      }
      parsed[key] = value;
    }
    return parsed;
  }

  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return 'Unknown error.';
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  bool _matchesScene({
    required ObsRuntimeState obs,
    required String? activeSceneName,
    required String? targetId,
    required String? targetName,
  }) {
    if (activeSceneName == null) return false;

    if (targetId != null && targetId.isNotEmpty) {
      if (activeSceneName == targetId) return true;
      for (final scene in obs.scenes) {
        if (scene.id == targetId || scene.name == targetId) {
          if (scene.name == activeSceneName || scene.id == activeSceneName) {
            return true;
          }
        }
      }
    }

    if (targetName != null && targetName.isNotEmpty) {
      if (activeSceneName == targetName) return true;
      for (final scene in obs.scenes) {
        if (scene.name == targetName || scene.id == targetName) {
          if (scene.name == activeSceneName || scene.id == activeSceneName) {
            return true;
          }
        }
      }
    }

    return false;
  }

  @override
  void dispose() {
    _bannerAutoHideTimer?.cancel();
    _scenePreviewRefreshTimer?.cancel();
    _activeScenePreviewRefreshTimer?.cancel();
    _obsSub?.cancel();
    super.dispose();
  }
}

final controllerControllerProvider =
    StateNotifierProvider<ControllerController, ControllerScreenState>((ref) {
  return ControllerController(
    loadPages: ref.watch(loadControllerPagesUseCaseProvider),
    controllerRepository: ref.watch(controllerRepositoryProvider),
    executeButtonAction: ref.watch(executeButtonActionUseCaseProvider),
    runMacro: ref.watch(runMacroUseCaseProvider),
    ref: ref,
  );
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
