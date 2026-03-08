import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/controller_page.dart';
import '../../../../domain/repositories/controller_repository.dart';
import '../../../../shared/state/app_providers.dart';

class PageManagerState {
  const PageManagerState({
    required this.pages,
    this.isLoading = false,
  });

  final List<ControllerPage> pages;
  final bool isLoading;

  PageManagerState copyWith({
    List<ControllerPage>? pages,
    bool? isLoading,
  }) {
    return PageManagerState(
      pages: pages ?? this.pages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PageManagerController extends StateNotifier<PageManagerState> {
  PageManagerController(this._repository)
      : super(const PageManagerState(
            pages: <ControllerPage>[], isLoading: true)) {
    _load();
  }

  final ControllerRepository _repository;

  Future<void> _load() async {
    final pages = await _repository.loadPages();
    state = state.copyWith(pages: pages, isLoading: false);
  }

  Future<void> setDefault(String pageId) async {
    final updated = state.pages
        .map((page) => page.copyWith(isDefault: page.id == pageId))
        .toList();
    await _persist(updated);
  }

  Future<String> createPage({String? name}) async {
    final id = 'page_${DateTime.now().millisecondsSinceEpoch}';
    final created = ControllerPage(
      id: id,
      name: (name == null || name.trim().isEmpty) ? 'New Page' : name.trim(),
      columns: AppConstants.defaultPageColumns,
      rows: AppConstants.defaultPageRows,
      buttons: const [],
      isDefault: state.pages.isEmpty,
    );

    final updated = <ControllerPage>[...state.pages, created];
    await _persist(updated);
    return id;
  }

  Future<void> renamePage(String pageId, String name) async {
    final updated = state.pages
        .map((page) => page.id == pageId ? page.copyWith(name: name) : page)
        .toList();
    await _persist(updated);
  }

  Future<void> duplicatePage(String pageId) async {
    final source = state.pages.where((page) => page.id == pageId).firstOrNull;
    if (source == null) return;

    final duplicate = source.copyWith(
      id: 'page_${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} Copy',
      isDefault: false,
    );

    final updated = <ControllerPage>[...state.pages, duplicate];
    await _persist(updated);
  }

  Future<void> deletePage(String pageId) async {
    if (state.pages.length <= 1) return;

    var updated = state.pages.where((page) => page.id != pageId).toList();
    if (!updated.any((page) => page.isDefault)) {
      updated = updated
          .asMap()
          .entries
          .map((entry) => entry.value.copyWith(isDefault: entry.key == 0))
          .toList();
    }

    await _persist(updated);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final updated = <ControllerPage>[...state.pages];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);

    await _persist(updated);
  }

  Future<void> _persist(List<ControllerPage> pages) async {
    state = state.copyWith(pages: pages);
    await _repository.savePages(pages);
  }
}

final pageManagerControllerProvider =
    StateNotifierProvider<PageManagerController, PageManagerState>((ref) {
  return PageManagerController(ref.watch(controllerRepositoryProvider));
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
