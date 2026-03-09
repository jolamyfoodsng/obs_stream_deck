class FakeSceneThumbnailService {
  FakeSceneThumbnailService({Map<String, String>? thumbnails})
      : thumbnails = thumbnails ?? <String, String>{};

  final Map<String, String> thumbnails;

  String? thumbnailFor(String sceneName) => thumbnails[sceneName];
}
