import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/review_prompt_service.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/obs_runtime_state.dart';
import '../../domain/entities/stream_status.dart';
import '../../domain/repositories/obs_repository.dart';

class AppEngagementState {
  const AppEngagementState({
    required this.installDate,
    required this.appOpenCount,
    required this.successfulObsConnections,
    required this.successfulStreamStarts,
    required this.tutorialCompleted,
    required this.tutorialPending,
    this.lastReviewPromptAt,
    this.onboardingActive = false,
    this.ready = false,
  });

  final DateTime installDate;
  final int appOpenCount;
  final int successfulObsConnections;
  final int successfulStreamStarts;
  final DateTime? lastReviewPromptAt;
  final bool tutorialCompleted;
  final bool tutorialPending;
  final bool onboardingActive;
  final bool ready;

  AppEngagementState copyWith({
    DateTime? installDate,
    int? appOpenCount,
    int? successfulObsConnections,
    int? successfulStreamStarts,
    DateTime? lastReviewPromptAt,
    bool clearLastReviewPromptAt = false,
    bool? tutorialCompleted,
    bool? tutorialPending,
    bool? onboardingActive,
    bool? ready,
  }) {
    return AppEngagementState(
      installDate: installDate ?? this.installDate,
      appOpenCount: appOpenCount ?? this.appOpenCount,
      successfulObsConnections:
          successfulObsConnections ?? this.successfulObsConnections,
      successfulStreamStarts:
          successfulStreamStarts ?? this.successfulStreamStarts,
      lastReviewPromptAt: clearLastReviewPromptAt
          ? null
          : (lastReviewPromptAt ?? this.lastReviewPromptAt),
      tutorialCompleted: tutorialCompleted ?? this.tutorialCompleted,
      tutorialPending: tutorialPending ?? this.tutorialPending,
      onboardingActive: onboardingActive ?? this.onboardingActive,
      ready: ready ?? this.ready,
    );
  }

  factory AppEngagementState.initial() {
    return AppEngagementState(
      installDate: DateTime.now(),
      appOpenCount: 0,
      successfulObsConnections: 0,
      successfulStreamStarts: 0,
      tutorialCompleted: false,
      tutorialPending: false,
      ready: false,
    );
  }
}

class AppEngagementController extends StateNotifier<AppEngagementState> {
  AppEngagementController({
    required LocalStorageService localStorage,
    required ObsRepository obsRepository,
    required ReviewPromptService reviewPromptService,
  })  : _localStorage = localStorage,
        _obsRepository = obsRepository,
        _reviewPromptService = reviewPromptService,
        super(AppEngagementState.initial()) {
    _init();
  }

  final LocalStorageService _localStorage;
  final ObsRepository _obsRepository;
  final ReviewPromptService _reviewPromptService;

  StreamSubscription<ObsRuntimeState>? _obsStateSubscription;
  ObsRuntimeState? _lastObsState;
  bool _reviewRequestInFlight = false;

  Future<void> _init() async {
    final installDate =
        _readDate(StorageKeys.installTimestamp) ?? DateTime.now();
    final appOpens = _readInt(StorageKeys.appOpenCount);
    final successConnections = _readInt(StorageKeys.successfulObsConnections);
    final streamStarts = _readInt(StorageKeys.successfulStreamStarts);
    final lastReviewAt = _readDate(StorageKeys.lastReviewPromptAt);
    final tutorialCompleted =
        _localStorage.getBool(StorageKeys.tutorialCompleted) ?? false;
    final storedTutorialPending =
        _localStorage.getBool(StorageKeys.tutorialPending) ?? false;
    final tutorialPending =
        tutorialCompleted ? false : (storedTutorialPending && appOpens <= 1);

    await _persistDate(StorageKeys.installTimestamp, installDate);

    state = state.copyWith(
      installDate: installDate,
      appOpenCount: appOpens,
      successfulObsConnections: successConnections,
      successfulStreamStarts: streamStarts,
      lastReviewPromptAt: lastReviewAt,
      tutorialCompleted: tutorialCompleted,
      tutorialPending: tutorialPending,
      ready: true,
    );

    if (storedTutorialPending != tutorialPending) {
      await _persistBool(StorageKeys.tutorialPending, tutorialPending);
    }

    _obsStateSubscription =
        _obsRepository.watchState().listen(_onObsStateChanged);
  }

  Future<void> recordAppOpen() async {
    if (!state.ready) return;
    final nextCount = state.appOpenCount + 1;
    var pending = state.tutorialPending;
    if (nextCount == 1 && !state.tutorialCompleted) {
      pending = true;
    }

    state = state.copyWith(appOpenCount: nextCount, tutorialPending: pending);
    await _persistInt(StorageKeys.appOpenCount, nextCount);
    await _persistBool(StorageKeys.tutorialPending, pending);
  }

  Future<void> setOnboardingActive(bool active) async {
    state = state.copyWith(onboardingActive: active);
  }

  Future<void> completeTutorial() async {
    state = state.copyWith(
      tutorialCompleted: true,
      tutorialPending: false,
      onboardingActive: false,
    );
    await _persistBool(StorageKeys.tutorialCompleted, true);
    await _persistBool(StorageKeys.tutorialPending, false);
  }

  Future<void> requestTutorialReplay() async {
    state = state.copyWith(tutorialPending: true);
    await _persistBool(StorageKeys.tutorialPending, true);
  }

  Future<void> consumeTutorialPending() async {
    if (!state.tutorialPending) return;
    state = state.copyWith(tutorialPending: false);
    await _persistBool(StorageKeys.tutorialPending, false);
  }

  Future<bool> requestManualReview() async {
    return _requestReview(
        userInitiated: true, runtimeState: _obsRepository.currentState());
  }

  Future<bool> maybeRequestReviewIfEligible({
    required ObsRuntimeState runtimeState,
  }) async {
    return _requestReview(userInitiated: false, runtimeState: runtimeState);
  }

  Future<bool> _requestReview({
    required bool userInitiated,
    required ObsRuntimeState runtimeState,
  }) async {
    if (_reviewRequestInFlight || !state.ready) return false;
    if (!userInitiated && !_isEligibleForAutomaticReview(runtimeState)) {
      return false;
    }

    _reviewRequestInFlight = true;
    try {
      final available = await _reviewPromptService.isAvailable();
      if (available) {
        await _reviewPromptService.requestReview();
      } else {
        await _reviewPromptService.openStoreListing();
      }
      final now = DateTime.now();
      state = state.copyWith(lastReviewPromptAt: now);
      await _persistDate(StorageKeys.lastReviewPromptAt, now);
      return true;
    } catch (_) {
      return false;
    } finally {
      _reviewRequestInFlight = false;
    }
  }

  bool _isEligibleForAutomaticReview(ObsRuntimeState runtimeState) {
    if (state.onboardingActive) return false;
    if (runtimeState.connectionStatus != ConnectionStatus.connected) {
      return false;
    }
    if ((runtimeState.lastError ?? '').trim().isNotEmpty) return false;

    final installAge = DateTime.now().difference(state.installDate).inDays;
    if (installAge < AppConstants.reviewInstallMinDays) return false;

    if (state.appOpenCount < AppConstants.reviewMinAppOpens) return false;
    if (state.successfulObsConnections <
        AppConstants.reviewMinSuccessfulConnections) {
      return false;
    }

    final lastPromptAt = state.lastReviewPromptAt;
    if (lastPromptAt != null) {
      final daysSincePrompt = DateTime.now().difference(lastPromptAt).inDays;
      if (daysSincePrompt < AppConstants.reviewCooldownDays) {
        return false;
      }
    }

    return true;
  }

  Future<void> _onObsStateChanged(ObsRuntimeState runtimeState) async {
    final previous = _lastObsState;

    final connectedNow =
        runtimeState.connectionStatus == ConnectionStatus.connected;
    final wasConnected =
        previous?.connectionStatus == ConnectionStatus.connected;
    if (connectedNow && !wasConnected) {
      final nextCount = state.successfulObsConnections + 1;
      state = state.copyWith(
        successfulObsConnections: nextCount,
      );
      await _persistInt(StorageKeys.successfulObsConnections, nextCount);
      await maybeRequestReviewIfEligible(runtimeState: runtimeState);
    }

    final streamLiveNow = runtimeState.streamStatus == StreamStatus.live;
    final wasStreamLive = previous?.streamStatus == StreamStatus.live;
    if (streamLiveNow && !wasStreamLive) {
      final nextCount = state.successfulStreamStarts + 1;
      state = state.copyWith(successfulStreamStarts: nextCount);
      await _persistInt(StorageKeys.successfulStreamStarts, nextCount);
      await maybeRequestReviewIfEligible(runtimeState: runtimeState);
    }

    _lastObsState = runtimeState;
  }

  int _readInt(String key) {
    return _localStorage.getInt(key) ?? 0;
  }

  DateTime? _readDate(String key) {
    final raw = _localStorage.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _persistInt(String key, int value) async {
    await _localStorage.setString(key, '$value');
  }

  Future<void> _persistDate(String key, DateTime value) async {
    await _localStorage.setString(key, value.toIso8601String());
  }

  Future<void> _persistBool(String key, bool value) async {
    await _localStorage.setBool(key, value);
  }

  @override
  void dispose() {
    _obsStateSubscription?.cancel();
    super.dispose();
  }
}
