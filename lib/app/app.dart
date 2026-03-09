import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../shared/state/app_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class ObsStreamDeckApp extends ConsumerStatefulWidget {
  const ObsStreamDeckApp({
    super.key,
    this.routerConfig,
  });

  final GoRouter? routerConfig;

  @override
  ConsumerState<ObsStreamDeckApp> createState() => _ObsStreamDeckAppState();
}

class _ObsStreamDeckAppState extends ConsumerState<ObsStreamDeckApp>
    with WidgetsBindingObserver {
  late final _router = widget.routerConfig ?? AppRouter.router();
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appEngagementControllerProvider.notifier).recordAppOpen();
      ref.read(premiumControllerProvider);
      ref.read(obsRepositoryProvider).setAppInForeground(true);
      _bootstrapConnection();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    ref.read(obsRepositoryProvider).setAppInForeground(isForeground);
  }

  Future<void> _bootstrapConnection() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final connectionRepository = ref.read(connectionRepositoryProvider);
    final obsRepository = ref.read(obsRepositoryProvider);
    final saved = await connectionRepository.loadConfig();
    if (saved == null) return;
    try {
      await obsRepository.connect(saved);
    } catch (error, stackTrace) {
      developer.log(
        'Saved OBS connection bootstrap failed.',
        name: 'DeckPilot.Connection',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
