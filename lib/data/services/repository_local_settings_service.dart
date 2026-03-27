import '../database/database_helper.dart';
import '../models/repository_local_settings.dart';
import 'app_log_service.dart';

class RepositoryLocalSettingsService {
  static RepositoryLocalSettingsService? _instance;
  final DatabaseHelper _db;
  final AppLogService _appLog;

  RepositoryLocalSettingsService._({DatabaseHelper? db, AppLogService? appLog})
    : _db = db ?? DatabaseHelper.instance,
      _appLog = appLog ?? AppLogService.instance;

  static RepositoryLocalSettingsService get instance {
    _instance ??= RepositoryLocalSettingsService._();
    return _instance!;
  }

  Future<RepositoryLocalSettings> getSettings(String repositoryId) async {
    final existing = await _db.getRepositoryLocalSettings(repositoryId);
    if (existing != null) {
      return RepositoryLocalSettings.fromMap(existing);
    }

    final defaults = RepositoryLocalSettings.createDefault(repositoryId);
    await _db.upsertRepositoryLocalSettings(defaults.toMap());
    await _appLog.debug(
      category: 'settings',
      message: 'Repository local settings defaulted',
      source: 'RepositoryLocalSettingsService.getSettings',
      repositoryId: repositoryId,
    );
    return defaults;
  }

  Future<void> saveSettings(RepositoryLocalSettings settings) async {
    await _appLog.info(
      category: 'settings',
      message: 'Repository local settings saved',
      source: 'RepositoryLocalSettingsService.saveSettings',
      repositoryId: settings.repositoryId,
      context: {
        'maxVersions': settings.maxVersions,
        'maxVersionDays': settings.maxVersionDays,
        'maxVersionSizeGB': settings.maxVersionSizeGB,
      },
    );
    await _db.upsertRepositoryLocalSettings(settings.toMap());
  }

  Future<void> deleteSettings(String repositoryId) async {
    await _appLog.warning(
      category: 'settings',
      message: 'Repository local settings deleted',
      source: 'RepositoryLocalSettingsService.deleteSettings',
      repositoryId: repositoryId,
    );
    await _db.deleteRepositoryLocalSettings(repositoryId);
  }
}
