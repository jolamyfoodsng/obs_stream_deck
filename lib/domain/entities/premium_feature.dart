enum PremiumFeature {
  unlimitedPages,
  unlimitedScenes,
  macros,
  scenePreviews,
  streamHealthMonitoring,
  emergencyPage,
  advancedAutomation,
  internetRemote,
}

extension PremiumFeatureX on PremiumFeature {
  String get label {
    switch (this) {
      case PremiumFeature.unlimitedPages:
        return 'Unlimited deck pages';
      case PremiumFeature.unlimitedScenes:
        return 'Unlimited scene buttons';
      case PremiumFeature.macros:
        return 'Unlimited macros';
      case PremiumFeature.scenePreviews:
        return 'Scene preview thumbnails';
      case PremiumFeature.streamHealthMonitoring:
        return 'Stream health monitoring';
      case PremiumFeature.emergencyPage:
        return 'Emergency controls page';
      case PremiumFeature.advancedAutomation:
        return 'Advanced automation';
      case PremiumFeature.internetRemote:
        return 'Internet remote control';
    }
  }
}
