import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AppBottomNavTab { control, pages, macros, monitor, settings }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentTab,
    this.tabKeys,
  });

  final AppBottomNavTab currentTab;
  final Map<AppBottomNavTab, GlobalKey>? tabKeys;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentTab.index,
      onDestinationSelected: (index) {
        final tab = AppBottomNavTab.values[index];
        switch (tab) {
          case AppBottomNavTab.control:
            context.go('/controller');
            return;
          case AppBottomNavTab.pages:
            context.go('/page-manager');
            return;
          case AppBottomNavTab.macros:
            context.go('/macros');
            return;
          case AppBottomNavTab.monitor:
            context.go('/monitor');
            return;
          case AppBottomNavTab.settings:
            context.go('/settings');
            return;
        }
      },
      destinations: <NavigationDestination>[
        NavigationDestination(
          icon: _buildTabIcon(AppBottomNavTab.control, Icons.gamepad_outlined),
          label: 'Control',
        ),
        NavigationDestination(
          icon: _buildTabIcon(AppBottomNavTab.pages, Icons.layers_outlined),
          label: 'Pages',
        ),
        NavigationDestination(
          icon: _buildTabIcon(AppBottomNavTab.macros, Icons.bolt_outlined),
          label: 'Macros',
        ),
        NavigationDestination(
          icon: _buildTabIcon(
              AppBottomNavTab.monitor, Icons.monitor_heart_outlined),
          label: 'Monitor',
        ),
        NavigationDestination(
          icon:
              _buildTabIcon(AppBottomNavTab.settings, Icons.settings_outlined),
          label: 'Settings',
        ),
      ],
    );
  }

  Widget _buildTabIcon(AppBottomNavTab tab, IconData icon) {
    final key = tabKeys?[tab];
    if (key == null) {
      return Icon(icon);
    }
    return SizedBox(
      key: key,
      child: Icon(icon),
    );
  }
}
