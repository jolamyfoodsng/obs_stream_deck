import 'package:in_app_review/in_app_review.dart';

abstract class ReviewPromptService {
  Future<bool> isAvailable();
  Future<void> requestReview();
  Future<void> openStoreListing();
}

class InAppReviewPromptService implements ReviewPromptService {
  InAppReviewPromptService({InAppReview? inAppReview})
      : _inAppReview = inAppReview ?? InAppReview.instance;

  final InAppReview _inAppReview;

  @override
  Future<bool> isAvailable() {
    return _inAppReview.isAvailable();
  }

  @override
  Future<void> requestReview() {
    return _inAppReview.requestReview();
  }

  @override
  Future<void> openStoreListing() {
    return _inAppReview.openStoreListing(
      appStoreId: null,
      microsoftStoreId: null,
    );
  }
}
