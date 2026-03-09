enum ConnectionMethod {
  autoDetect,
  wifi,
  usb,
  manual,
}

extension ConnectionMethodX on ConnectionMethod {
  String get label {
    switch (this) {
      case ConnectionMethod.autoDetect:
        return 'Auto Detect';
      case ConnectionMethod.wifi:
        return 'Wi-Fi';
      case ConnectionMethod.usb:
        return 'USB';
      case ConnectionMethod.manual:
        return 'Manual';
    }
  }

  String get helper {
    switch (this) {
      case ConnectionMethod.autoDetect:
        return 'Find OBS on your local network automatically.';
      case ConnectionMethod.wifi:
        return 'Connect over your Wi-Fi/hotspot local network.';
      case ConnectionMethod.usb:
        return 'Use USB cable with ADB reverse or USB network interface.';
      case ConnectionMethod.manual:
        return 'Enter host/port/password manually.';
    }
  }
}

ConnectionMethod connectionMethodFromName(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return ConnectionMethod.autoDetect;
  }

  for (final method in ConnectionMethod.values) {
    if (method.name == raw) return method;
  }
  return ConnectionMethod.autoDetect;
}
