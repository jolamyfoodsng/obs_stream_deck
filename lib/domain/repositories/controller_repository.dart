import '../entities/controller_page.dart';

abstract class ControllerRepository {
  Future<List<ControllerPage>> loadPages();
  Future<void> savePages(List<ControllerPage> pages);
}
