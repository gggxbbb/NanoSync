import '../database/database_helper.dart';
import '../models/repository_local_settings.dart';

class RepositoryLocalSettingsService {
  static RepositoryLocalSettingsService? _instance;
  final DatabaseHelper _db;

  RepositoryLocalSettingsService._({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

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
    return defaults;
  }

  Future<void> saveSettings(RepositoryLocalSettings settings) async {
    await _db.upsertRepositoryLocalSettings(settings.toMap());
  }

  Future<void> deleteSettings(String repositoryId) async {
    await _db.deleteRepositoryLocalSettings(repositoryId);
  }
}
