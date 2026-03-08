import '../../data/datasources/controller_local_datasource.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/controller_button.dart';
import '../../domain/entities/controller_page.dart';
import '../../domain/repositories/controller_repository.dart';

class ControllerRepositoryImpl implements ControllerRepository {
  ControllerRepositoryImpl(this._dataSource);

  final ControllerLocalDataSource _dataSource;

  @override
  Future<List<ControllerPage>> loadPages() async {
    final saved = await _dataSource.loadPages();
    if (saved.isEmpty) {
      final initial = _initialPages();
      await _dataSource.savePages(initial);
      return initial;
    }

    final (sanitized, changed) = _sanitizeLegacySeededPages(saved);
    if (changed) {
      await _dataSource.savePages(sanitized);
    }
    return sanitized;
  }

  @override
  Future<void> savePages(List<ControllerPage> pages) =>
      _dataSource.savePages(pages);

  List<ControllerPage> _initialPages() {
    return const <ControllerPage>[
      ControllerPage(
        id: 'scenes',
        name: 'Scenes',
        columns: AppConstants.defaultPageColumns,
        rows: AppConstants.defaultPageRows,
        buttons: <ControllerButton>[],
        isDefault: true,
      ),
    ];
  }

  (List<ControllerPage>, bool) _sanitizeLegacySeededPages(
    List<ControllerPage> pages,
  ) {
    if (!_looksLikeLegacySeededPages(pages)) {
      return (pages, false);
    }
    return (_initialPages(), true);
  }

  bool _looksLikeLegacySeededPages(List<ControllerPage> pages) {
    final scenesPage = pages
        .where((page) => page.id.trim().toLowerCase() == 'scenes')
        .firstOrNull;
    if (scenesPage == null) return false;

    final ids = scenesPage.buttons.map((button) => button.id).toSet();
    const legacySceneButtonIds = <String>{
      'scene-intro',
      'scene-gaming',
      'scene-chat',
      'scene-outro',
    };
    final hasLegacySceneButtons = legacySceneButtonIds.every(ids.contains);
    if (!hasLegacySceneButtons) return false;

    final pageIds = pages.map((page) => page.id.trim().toLowerCase()).toSet();
    const legacyPageIds = <String>{'audio', 'media', 'emergency'};
    final hasLegacyPages = legacyPageIds.any(pageIds.contains);
    return hasLegacyPages;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
