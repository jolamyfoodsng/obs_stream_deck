enum ScenePreviewMode {
  off,
  staticThumbnails,
  autoRefresh10s,
  tapToRefresh,
}

ScenePreviewMode scenePreviewModeFromName(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return ScenePreviewMode.off;
  }

  for (final mode in ScenePreviewMode.values) {
    if (mode.name == raw) {
      return mode;
    }
  }

  return ScenePreviewMode.off;
}

extension ScenePreviewModeUi on ScenePreviewMode {
  String get label {
    switch (this) {
      case ScenePreviewMode.off:
        return 'Off';
      case ScenePreviewMode.staticThumbnails:
        return 'Static thumbnails';
      case ScenePreviewMode.autoRefresh10s:
        return 'Auto refresh (10s)';
      case ScenePreviewMode.tapToRefresh:
        return 'Tap to refresh';
    }
  }
}
