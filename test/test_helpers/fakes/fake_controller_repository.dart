import 'package:obs_stream_deck/domain/entities/controller_page.dart';
import 'package:obs_stream_deck/domain/repositories/controller_repository.dart';

class FakeControllerRepository implements ControllerRepository {
  List<ControllerPage> pages;

  FakeControllerRepository({List<ControllerPage>? pages})
      : pages = pages ?? <ControllerPage>[];

  @override
  Future<List<ControllerPage>> loadPages() async => List<ControllerPage>.from(pages);

  @override
  Future<void> savePages(List<ControllerPage> pages) async {
    this.pages = List<ControllerPage>.from(pages);
  }
}
