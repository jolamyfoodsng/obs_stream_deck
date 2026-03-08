import 'package:flutter/widgets.dart';
import '../constants/app_constants.dart';

enum DeviceType { mobile, tablet, desktop }

class Responsive {
  const Responsive._();

  static DeviceType deviceType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= AppConstants.tabletBreakpoint) return DeviceType.desktop;
    if (width >= AppConstants.mobileBreakpoint) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  static int gridColumns(BuildContext context) {
    final type = deviceType(context);
    switch (type) {
      case DeviceType.mobile:
        return AppConstants.mobileGridColumns;
      case DeviceType.tablet:
        return AppConstants.tabletGridColumns;
      case DeviceType.desktop:
        return AppConstants.desktopGridColumns;
    }
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final type = deviceType(context);
    switch (type) {
      case DeviceType.mobile:
        return const EdgeInsets.all(16);
      case DeviceType.tablet:
        return const EdgeInsets.all(20);
      case DeviceType.desktop:
        return const EdgeInsets.all(24);
    }
  }
}
