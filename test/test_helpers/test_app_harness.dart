import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obs_stream_deck/app/app.dart';
import 'package:obs_stream_deck/app/router.dart';
import 'package:obs_stream_deck/core/services/connection_diagnostics_service.dart';
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
import 'fakes/fake_connection_diagnostics_service.dart';
import 'fakes/fake_connection_repository.dart';
import 'fakes/fake_controller_repository.dart';
import 'fakes/fake_dashboard_repository.dart';
import 'fakes/fake_macro_repository.dart';
import 'fakes/fake_obs_repository.dart';
import 'fakes/fake_review_prompt_service.dart';

Widget buildTestApp({
  required SharedPreferences sharedPreferences,
  String initialLocation = '/controller',
  ObsRepository? obsRepository,
  ConnectionRepository? connectionRepository,
  ControllerRepository? controllerRepository,
  MacroRepository? macroRepository,
  DashboardRepository? dashboardRepository,
  PremiumBillingService? billingService,
  ReviewPromptService? reviewPromptService,
  FakeObsAutoDiscoveryService? autoDiscoveryService,
  ConnectionDiagnosticsService? diagnosticsService,
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

  return ProviderScope(
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
      connectionDiagnosticsServiceProvider.overrideWithValue(
        diagnosticsService ?? FakeConnectionDiagnosticsService(),
      ),
    ],
    child: ObsStreamDeckApp(
      routerConfig: AppRouter.router(initialLocation: initialLocation),
    ),
  );
}

Future<void> pumpTestApp(
  WidgetTester tester, {
  required SharedPreferences sharedPreferences,
  String initialLocation = '/controller',
  ObsRepository? obsRepository,
  ConnectionRepository? connectionRepository,
  ControllerRepository? controllerRepository,
  MacroRepository? macroRepository,
  DashboardRepository? dashboardRepository,
  PremiumBillingService? billingService,
  ReviewPromptService? reviewPromptService,
  FakeObsAutoDiscoveryService? autoDiscoveryService,
  ConnectionDiagnosticsService? diagnosticsService,
}) async {
  await tester.pumpWidget(
    buildTestApp(
      sharedPreferences: sharedPreferences,
      initialLocation: initialLocation,
      obsRepository: obsRepository,
      connectionRepository: connectionRepository,
      controllerRepository: controllerRepository,
      macroRepository: macroRepository,
      dashboardRepository: dashboardRepository,
      billingService: billingService,
      reviewPromptService: reviewPromptService,
      autoDiscoveryService: autoDiscoveryService,
      diagnosticsService: diagnosticsService,
    ),
  );
  await pumpAppFrames(tester);
}

Future<void> pumpAppFrames(
  WidgetTester tester, [
  Duration total = const Duration(milliseconds: 450),
]) async {
  await tester.pump();
  final ticks = (total.inMilliseconds / 16).ceil();
  for (var index = 0; index < ticks; index += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
