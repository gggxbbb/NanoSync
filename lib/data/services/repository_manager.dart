import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/repository_config.dart';
import '../vc_database.dart';
import 'vc_engine.dart';

class Repository {
  final String id;
  final String localPath;
  final String name;
  final DateTime? lastAccessed;
  final DateTime addedAt;
  final RepositoryConfig? config;

  Repository({
    required this.id,
    required this.localPath,
    required this.name,
    this.lastAccessed,
    required this.addedAt,
    this.config,
  });

  factory Repository.fromMap(
    Map<String, dynamic> map, {
    RepositoryConfig? config,
  }) {
    return Repository(
      id: map['id'] as String,
      localPath: map['local_path'] as String,
      name: map['name'] as String,
      lastAccessed: map['last_accessed'] != null
          ? DateTime.parse(map['last_accessed'] as String)
          : null,
      addedAt: DateTime.parse(map['added_at'] as String),
      config: config,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'local_path': localPath,
      'name': name,
      'last_accessed': lastAccessed?.toIso8601String(),
      'added_at': addedAt.toIso8601String(),
    };
  }
}

class RepositoryManager {
  static RepositoryManager? _instance;
  final DatabaseHelper _db;
  final VcDatabase _vcDb;

  RepositoryManager._({DatabaseHelper? db, VcDatabase? vcDb})
    : _db = db ?? DatabaseHelper.instance,
      _vcDb = vcDb ?? VcDatabase.instance;

  static RepositoryManager get instance {
    _instance ??= RepositoryManager._();
    return _instance!;
  }

  Future<Repository> registerRepository(
    String localPath, {
    String? name,
  }) async {
    final normalizedPath = _normalizePath(localPath);
    final existing = await _db.getRegisteredRepositoryByPath(normalizedPath);
    if (existing != null) {
      final config = await RepositoryConfig.loadFromFile(
        await RepositoryConfig.getConfigPath(normalizedPath),
      );
      await _db.updateRegisteredRepository(existing['id'] as String, {
        'last_accessed': DateTime.now().toIso8601String(),
      });
      return Repository.fromMap(existing, config: config);
    }

    final repoName = name ?? p.basename(normalizedPath);
    final config = await RepositoryConfig.loadFromFile(
      await RepositoryConfig.getConfigPath(normalizedPath),
    );

    final repoId = config?.id ?? const Uuid().v4();
    final now = DateTime.now();

    final repo = Repository(
      id: repoId,
      localPath: normalizedPath,
      name: repoName,
      addedAt: now,
      config: config,
    );

    await _db.insertRegisteredRepository(repo.toMap());
    return repo;
  }

  Future<void> unregisterRepository(String repositoryId) async {
    await _db.deleteRepositoryRemotesByRepository(repositoryId);
    await _db.deleteRegisteredRepository(repositoryId);
  }

  Future<List<Repository>> listRepositories() async {
    final maps = await _db.getAllRegisteredRepositories();
    final repos = <Repository>[];

    for (final map in maps) {
      final config = await RepositoryConfig.loadFromFile(
        await RepositoryConfig.getConfigPath(map['local_path'] as String),
      );
      repos.add(Repository.fromMap(map, config: config));
    }

    return repos;
  }

  Future<Repository?> getRepository(String repositoryId) async {
    final map = await _db.getRegisteredRepository(repositoryId);
    if (map == null) return null;

    final config = await RepositoryConfig.loadFromFile(
      await RepositoryConfig.getConfigPath(map['local_path'] as String),
    );
    return Repository.fromMap(map, config: config);
  }

  Future<Repository?> getRepositoryByPath(String localPath) async {
    final map = await _db.getRegisteredRepositoryByPath(
      _normalizePath(localPath),
    );
    if (map == null) return null;

    final config = await RepositoryConfig.loadFromFile(
      await RepositoryConfig.getConfigPath(map['local_path'] as String),
    );
    return Repository.fromMap(map, config: config);
  }

  Future<Repository> importExisting(
    String localPath, {
    String? name,
    IgnoreConfig? ignoreConfig,
    String? remoteName,
    String? remotePath,
  }) async {
    final normalizedPath = _normalizePath(localPath);
    final dir = Directory(normalizedPath);

    if (!await dir.exists()) {
      throw Exception('Directory does not exist: $normalizedPath');
    }

    final nanosyncDir = Directory(p.join(normalizedPath, '.nanosync'));
    RepositoryConfig config;

    if (await nanosyncDir.exists()) {
      config =
          await RepositoryConfig.loadFromFile(
            await RepositoryConfig.getConfigPath(normalizedPath),
          ) ??
          RepositoryConfig(
            name: name ?? p.basename(normalizedPath),
            ignore: ignoreConfig ?? const IgnoreConfig(),
          );
    } else {
      config = RepositoryConfig(
        name: name ?? p.basename(normalizedPath),
        ignore: ignoreConfig ?? const IgnoreConfig(),
      );
      await config.saveToFile(normalizedPath);
    }

    final repo = await registerRepository(normalizedPath, name: name);

    final vcRepo = await _vcDb.getRepositoryByLocalPath(normalizedPath);
    if (vcRepo == null) {
      await _vcDb.insertRepository({
        'id': repo.id,
        'name': config.name,
        'local_path': normalizedPath,
        'current_branch_id': '',
        'head_commit_id': '',
        'is_initialized': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    final engine = VcEngine(repositoryId: repo.id, db: _vcDb);
    final statusResult = await engine.status();
    if (!statusResult.isSuccess ||
        (statusResult.data as VcRepositoryStatus).isInitialized == false) {
      await engine.init(
        name: config.defaultBranch,
        ignoreRules: config.ignore.toIgnoreRules(),
      );
    }

    // 注册仓库时必须创建初始提交
    await engine.add(all: true);
    await engine.commit(message: 'Initial commit');

    if (remoteName != null && remotePath != null && remotePath.isNotEmpty) {
      final existingRemote = await _db.getRemoteConnectionByName(remoteName);
      if (existingRemote != null) {
        await _db.insertRepositoryRemote({
          'id': const Uuid().v4(),
          'repository_id': repo.id,
          'remote_name': remoteName,
          'remote_path': remotePath,
          'is_default': 1,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }

    return repo;
  }

  Future<Repository> clone({
    required String connectionName,
    required String remotePath,
    required String localPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    final conn = await _db.getRemoteConnectionByName(connectionName);
    if (conn == null) {
      throw Exception('Remote connection not found: $connectionName');
    }

    final normalizedLocalPath = _normalizePath(localPath);
    final dir = Directory(normalizedLocalPath);
    await dir.create(recursive: true);

    onProgress?.call(0.1, 'Downloading repository metadata...');

    final config = await _downloadRepositoryConfig(
      conn,
      remotePath,
      normalizedLocalPath,
    );

    onProgress?.call(0.2, 'Initializing local repository...');

    final repo = await importExisting(normalizedLocalPath, name: config?.name);

    await _db.insertRepositoryRemote({
      'id': const Uuid().v4(),
      'repository_id': repo.id,
      'remote_name': connectionName,
      'remote_path': remotePath,
      'is_default': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    onProgress?.call(0.3, 'Downloading objects...');

    await _downloadObjects(conn, remotePath, normalizedLocalPath, (progress) {
      onProgress?.call(0.3 + progress * 0.6, 'Downloading objects...');
    });

    onProgress?.call(0.95, 'Restoring working directory...');

    final engine = VcEngine(repositoryId: repo.id, db: _vcDb);
    final status = await engine.status();
    if (status.isSuccess) {
      final repoStatus = status.data as VcRepositoryStatus;
      if (repoStatus.headCommitId.isNotEmpty) {
        await engine.reset(all: true, hard: true);
      }
    }

    onProgress?.call(1.0, 'Clone complete');

    return repo;
  }

  Future<void> updateRepositoryConfig(Repository repo) async {
    if (repo.config != null) {
      await repo.config!.saveToFile(repo.localPath);
    }
    await _db.updateRegisteredRepository(repo.id, {
      'name': repo.name,
      'last_accessed': DateTime.now().toIso8601String(),
    });
  }

  /// 删除仓库（可选择是否删除 .nanosync 文件夹）
  Future<void> deleteRepository(
    String repositoryId, {
    bool deleteNanosyncFolder = false,
  }) async {
    final repo = await getRepository(repositoryId);
    if (repo == null) return;

    // 从数据库中注销仓库
    await unregisterRepository(repositoryId);

    // 从版本控制数据库中删除
    await _vcDb.deleteRepository(repositoryId);

    // 如果需要删除 .nanosync 文件夹
    if (deleteNanosyncFolder) {
      final nanosyncDir = Directory(p.join(repo.localPath, '.nanosync'));
      if (await nanosyncDir.exists()) {
        await nanosyncDir.delete(recursive: true);
      }
    }
  }

  /// 迁移仓库到新路径
  Future<Repository> migrateRepository(
    String repositoryId,
    String newLocalPath, {
    void Function(double progress, String message)? onProgress,
  }) async {
    final repo = await getRepository(repositoryId);
    if (repo == null) {
      throw Exception('Repository not found: $repositoryId');
    }

    final normalizedNewPath = _normalizePath(newLocalPath);
    final oldPath = repo.localPath;

    if (oldPath == normalizedNewPath) {
      return repo;
    }

    // 检查目标路径是否已存在
    final newDir = Directory(normalizedNewPath);
    if (await newDir.exists()) {
      throw Exception('Target directory already exists: $normalizedNewPath');
    }

    onProgress?.call(0.1, 'Checking source directory...');

    final oldDir = Directory(oldPath);
    if (!await oldDir.exists()) {
      throw Exception('Source directory does not exist: $oldPath');
    }

    onProgress?.call(0.2, 'Moving repository files...');

    // 移动整个目录
    await oldDir.rename(normalizedNewPath);

    onProgress?.call(0.8, 'Updating database records...');

    // 更新数据库中的路径
    await _db.updateRegisteredRepository(repositoryId, {
      'local_path': normalizedNewPath,
      'last_accessed': DateTime.now().toIso8601String(),
    });

    // 更新版本控制数据库中的路径
    await _vcDb.updateRepository(repositoryId, {
      'local_path': normalizedNewPath,
      'updated_at': DateTime.now().toIso8601String(),
    });

    onProgress?.call(1.0, 'Migration complete');

    // 返回更新后的仓库对象
    return (await getRepository(repositoryId))!;
  }

  String _normalizePath(String path) {
    return p.normalize(path).replaceAll('/', Platform.pathSeparator);
  }

  Future<RepositoryConfig?> _downloadRepositoryConfig(
    Map<String, dynamic> conn,
    String remotePath,
    String localPath,
  ) async {
    return null;
  }

  Future<void> _downloadObjects(
    Map<String, dynamic> conn,
    String remotePath,
    String localPath,
    void Function(double progress)? onProgress,
  ) async {}
}
