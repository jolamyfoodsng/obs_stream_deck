import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/button_editor/presentation/pages/button_editor_screen.dart';
import '../features/connection/presentation/pages/connection_screen.dart';
import '../features/controller/presentation/pages/controller_screen.dart';
import '../features/dashboard/presentation/pages/dashboard_screen.dart';
import '../features/macro_editor/presentation/pages/macro_editor_screen.dart';
import '../features/macro_editor/presentation/pages/macro_library_screen.dart';
import '../features/page_manager/presentation/pages/page_manager_screen.dart';
import '../features/settings/presentation/pages/settings_screen.dart';
import '../features/splash/presentation/pages/splash_screen.dart';

class AppRouter {
  const AppRouter._();

  static GoRouter router() {
    return GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          name: 'splash',
          builder: (_, __) => const SplashScreen(),
        ),
        GoRoute(
          path: '/connection',
          name: 'connection',
          builder: (_, __) => const ConnectionScreen(),
        ),
        GoRoute(
          path: '/controller',
          name: 'controller',
          builder: (_, state) => ControllerScreen(
            initialPageId: state.uri.queryParameters['pageId'],
          ),
        ),
        GoRoute(
          path: '/button-editor',
          name: 'buttonEditor',
          builder: (_, state) {
            final buttonId = state.uri.queryParameters['buttonId'];
            final pageId = state.uri.queryParameters['pageId'];
            final slot = int.tryParse(state.uri.queryParameters['slot'] ?? '');
            return ButtonEditorScreen(
              buttonId: buttonId,
              pageId: pageId,
              slotPosition: slot,
            );
          },
        ),
        GoRoute(
          path: '/page-manager',
          name: 'pageManager',
          builder: (_, __) => const PageManagerScreen(),
        ),
        GoRoute(
          path: '/macros',
          name: 'macros',
          builder: (_, __) => const MacroLibraryScreen(),
        ),
        GoRoute(
          path: '/macro-editor',
          name: 'macroEditor',
          builder: (_, state) {
            final macroId = state.uri.queryParameters['macroId'];
            return MacroEditorScreen(macroId: macroId);
          },
        ),
        GoRoute(
          path: '/monitor',
          name: 'monitor',
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          redirect: (_, __) => '/monitor',
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (_, __) => const SettingsScreen(),
        ),
      ],
      errorBuilder: (_, state) => Scaffold(
        body: Center(
          child: Text('Route not found: ${state.uri}'),
        ),
      ),
    );
  }
}
