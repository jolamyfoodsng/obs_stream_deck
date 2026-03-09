import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obs_stream_deck/core/services/premium_billing_service.dart';
import 'package:obs_stream_deck/core/services/review_prompt_service.dart';
import 'package:obs_stream_deck/data/repositories/dashboard_repository_impl.dart';
import 'package:obs_stream_deck/domain/repositories/connection_repository.dart';
import 'package:obs_stream_deck/domain/repositories/controller_repository.dart';
import 'package:obs_stream_deck/domain/repositories/dashboard_repository.dart';
import 'package:obs_stream_deck/domain/repositories/macro_repository.dart';
import 'package:obs_stream_deck/domain/repositories/obs_repository.dart';
import 'package:obs_stream_deck/shared/state/app_providers.dart';

import 'fakes/fake_auto_discovery_service.dart';
import 'fakes/fake_billing_service.dart';
import 'fakes/fake_connection_repository.dart';
import 'fakes/fake_controller_repository.dart';
import 'fakes/fake_dashboard_repository.dart';
import 'fakes/fake_macro_repository.dart';
import 'fakes/fake_obs_repository.dart';
import 'fakes/fake_review_prompt_service.dart';

ProviderContainer createTestContainer({
  required SharedPreferences sharedPreferences,
  ObsRepository? obsRepository,
  ConnectionRepository? connectionRepository,
  ControllerRepository? controllerRepository,
  MacroRepository? macroRepository,
  DashboardRepository? dashboardRepository,
  PremiumBillingService? billingService,
  ReviewPromptService? reviewPromptService,
  FakeObsAutoDiscoveryService? autoDiscoveryService,
}) {
  final resolvedObsRepository = obsRepository ?? FakeObsRepository();
  final resolvedConnectionRepository =
      connectionRepository ?? FakeConnectionRepository();
  final resolvedControllerRepository =
      controllerRepository ?? FakeControllerRepository();
  final resolvedMacroRepository = macroRepository ?? FakeMacroRepository();
  final resolvedDashboardRepository = dashboardRepository ??
      (resolvedObsRepository is FakeObsRepository
          ? DashboardRepositoryImpl(resolvedObsRepository)
          : FakeDashboardRepository());

  return ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      obsRepositoryProvider.overrideWithValue(resolvedObsRepository),
      connectionRepositoryProvider.overrideWithValue(resolvedConnectionRepository),
      controllerRepositoryProvider.overrideWithValue(resolvedControllerRepository),
      macroRepositoryProvider.overrideWithValue(resolvedMacroRepository),
      dashboardRepositoryProvider.overrideWithValue(resolvedDashboardRepository),
      premiumBillingServiceProvider.overrideWithValue(
        billingService ?? FakeBillingService(),
      ),
      reviewPromptServiceProvider.overrideWithValue(
        reviewPromptService ?? FakeReviewPromptService(),
      ),
      obsAutoDiscoveryServiceProvider.overrideWithValue(
        autoDiscoveryService ?? FakeObsAutoDiscoveryService(),
      ),
    ],
  );
}

Future<void> settleContainer([
  int turns = 24,
  Duration delay = const Duration(milliseconds: 10),
]) async {
  for (var index = 0; index < turns; index += 1) {
    await Future<void>.delayed(delay);
  }
}
