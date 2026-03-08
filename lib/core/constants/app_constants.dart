class AppConstants {
  const AppConstants._();

  static const bool useMockObsService =
      bool.fromEnvironment('USE_MOCK_OBS', defaultValue: false);
  static const String appTitle = 'DeckPilot for OBS';
  static const String androidApplicationId = 'com.example.obs_stream_deck';

  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;

  static const int mobileGridColumns = 4;
  static const int mobileGridRows = 3;
  static const int tabletGridColumns = 6;
  static const int tabletGridRows = 4;
  static const int desktopGridColumns = 8;
  static const int desktopGridRows = 4;

  static const int defaultPageColumns = 3;
  static const int defaultPageRows = 4;

  static const int reviewInstallMinDays = 3;
  static const int reviewMinAppOpens = 5;
  static const int reviewMinSuccessfulConnections = 3;
  static const int reviewCooldownDays = 30;
}
