import 'package:obs_stream_deck/core/services/review_prompt_service.dart';

class FakeReviewPromptService implements ReviewPromptService {
  bool available;
  int isAvailableCalls = 0;
  int requestReviewCalls = 0;
  int openStoreListingCalls = 0;

  FakeReviewPromptService({this.available = true});

  @override
  Future<bool> isAvailable() async {
    isAvailableCalls += 1;
    return available;
  }

  @override
  Future<void> openStoreListing() async {
    openStoreListingCalls += 1;
  }

  @override
  Future<void> requestReview() async {
    requestReviewCalls += 1;
  }
}
