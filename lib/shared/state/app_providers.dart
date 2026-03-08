import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/layout_preset_service.dart';
import '../../core/services/mock_obs_websocket_service.dart';
import '../../core/services/obs_auto_discovery_service.dart';
import '../../core/services/obs_websocket_service.dart';
import '../../core/services/real_obs_websocket_service.dart';
import '../../data/datasources/connection_local_datasource.dart';
import '../../data/datasources/controller_local_datasource.dart';
import '../../data/datasources/macro_local_datasource.dart';
import '../../data/repositories/connection_repository_impl.dart';
import '../../data/repositories/controller_repository_impl.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../data/repositories/macro_repository_impl.dart';
import '../../data/repositories/obs_repository_impl.dart';
import '../../domain/entities/obs_runtime_state.dart';
import '../../domain/entities/scene_preview_mode.dart';
import '../../domain/repositories/connection_repository.dart';
import '../../domain/repositories/controller_repository.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/repositories/macro_repository.dart';
import '../../domain/repositories/obs_repository.dart';
import '../../domain/usecases/connect_to_obs_usecase.dart';
import '../../domain/usecases/execute_button_action_usecase.dart';
import '../../domain/usecases/load_controller_pages_usecase.dart';
import '../../domain/usecases/run_macro_usecase.dart';
import 'app_engagement_controller.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService(ref.watch(sharedPreferencesProvider));
});

final inAppReviewProvider = Provider<InAppReview>((ref) {
  return InAppReview.instance;
});

final obsAutoDiscoveryServiceProvider =
    Provider<ObsAutoDiscoveryService>((ref) {
  return const ObsAutoDiscoveryService();
});

final obsWebSocketServiceProvider = Provider<ObsWebSocketService>((ref) {
  final service = AppConstants.useMockObsService
      ? MockObsWebSocketService()
      : RealObsWebSocketService();

  ref.onDispose(() {
    if (service is MockObsWebSocketService) {
      service.dispose();
    } else if (service is RealObsWebSocketService) {
      service.dispose();
    }
  });

  return service;
});

final connectionDataSourceProvider = Provider<ConnectionLocalDataSource>((ref) {
  return ConnectionLocalDataSource(ref.watch(localStorageServiceProvider));
});

final controllerDataSourceProvider = Provider<ControllerLocalDataSource>((ref) {
  return ControllerLocalDataSource(ref.watch(localStorageServiceProvider));
});

final macroDataSourceProvider = Provider<MacroLocalDataSource>((ref) {
  return MacroLocalDataSource(ref.watch(localStorageServiceProvider));
});

final connectionRepositoryProvider = Provider<ConnectionRepository>((ref) {
  return ConnectionRepositoryImpl(ref.watch(connectionDataSourceProvider));
});

final controllerRepositoryProvider = Provider<ControllerRepository>((ref) {
  return ControllerRepositoryImpl(ref.watch(controllerDataSourceProvider));
});

final macroRepositoryProvider = Provider<MacroRepository>((ref) {
  return MacroRepositoryImpl(ref.watch(macroDataSourceProvider));
});

final obsRepositoryProvider = Provider<ObsRepository>((ref) {
  return ObsRepositoryImpl(
    service: ref.watch(obsWebSocketServiceProvider),
    macroRepository: ref.watch(macroRepositoryProvider),
  );
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(ref.watch(obsRepositoryProvider));
});

final layoutPresetServiceProvider = Provider<LayoutPresetService>((ref) {
  return LayoutPresetService(
    controllerRepository: ref.watch(controllerRepositoryProvider),
    macroRepository: ref.watch(macroRepositoryProvider),
    connectionRepository: ref.watch(connectionRepositoryProvider),
    localStorage: ref.watch(localStorageServiceProvider),
  );
});

final connectToObsUseCaseProvider = Provider<ConnectToObsUseCase>((ref) {
  return ConnectToObsUseCase(
    connectionRepository: ref.watch(connectionRepositoryProvider),
    obsRepository: ref.watch(obsRepositoryProvider),
  );
});

final executeButtonActionUseCaseProvider =
    Provider<ExecuteButtonActionUseCase>((ref) {
  return ExecuteButtonActionUseCase(ref.watch(obsRepositoryProvider));
});

final runMacroUseCaseProvider = Provider<RunMacroUseCase>((ref) {
  return RunMacroUseCase(ref.watch(obsRepositoryProvider));
});

final loadControllerPagesUseCaseProvider =
    Provider<LoadControllerPagesUseCase>((ref) {
  return LoadControllerPagesUseCase(ref.watch(controllerRepositoryProvider));
});

final obsRuntimeStateProvider = StreamProvider<ObsRuntimeState>((ref) {
  return ref.watch(obsRepositoryProvider).watchState();
});

class VolunteerModeController extends StateNotifier<bool> {
  VolunteerModeController(this._storage)
      : super(_storage.getBool(StorageKeys.volunteerMode) ?? false);

  final LocalStorageService _storage;

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _storage.setBool(StorageKeys.volunteerMode, enabled);
  }
}

final volunteerModeProvider =
    StateNotifierProvider<VolunteerModeController, bool>((ref) {
  return VolunteerModeController(ref.watch(localStorageServiceProvider));
});

class ScenePreviewModeController extends StateNotifier<ScenePreviewMode> {
  ScenePreviewModeController(this._storage)
      : super(
          scenePreviewModeFromName(
            _storage.getString(StorageKeys.scenePreviewMode),
          ),
        );

  final LocalStorageService _storage;

  Future<void> setMode(ScenePreviewMode mode) async {
    state = mode;
    await _storage.setString(StorageKeys.scenePreviewMode, mode.name);
  }
}

final scenePreviewModeProvider =
    StateNotifierProvider<ScenePreviewModeController, ScenePreviewMode>((ref) {
  return ScenePreviewModeController(ref.watch(localStorageServiceProvider));
});

final appEngagementControllerProvider =
    StateNotifierProvider<AppEngagementController, AppEngagementState>((ref) {
  return AppEngagementController(
    localStorage: ref.watch(localStorageServiceProvider),
    obsRepository: ref.watch(obsRepositoryProvider),
    inAppReview: ref.watch(inAppReviewProvider),
  );
});
