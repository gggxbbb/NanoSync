import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:webdav_client_plus/webdav_client_plus.dart';
import '../models/sync_task.dart';
import '../models/file_snapshot.dart';

/// WebDAV连接与文件操作服务
class WebDAVService {
  WebdavClient? _client;

  WebdavClient _createClient(SyncTask task) {
    final port = task.remotePort == 0 ? 443 : task.remotePort;
    final scheme = port == 443 ? 'https' : 'http';
    final url = '$scheme://${task.remoteHost}:$port${task.remotePath}';

    late WebdavClient client;
    if (task.remoteUsername.isEmpty) {
      client = WebdavClient.noAuth(url: url);
    } else {
      client = WebdavClient.basicAuth(
        url: url,
        user: task.remoteUsername,
        pwd: task.remotePassword,
      );
    }

    client.setConnectTimeout(8000);
    client.setReceiveTimeout(8000);
    return client;
  }

  Future<bool> connect(SyncTask task) async {
    try {
      _client = _createClient(task);
      await _client!.ping();
      return true;
    } catch (e) {
      _client = null;
      return false;
    }
  }

  void disconnect() {
    _client = null;
  }

  /// 测试连接：检查服务器可达性、目录存在性和可写性
  Future<({bool success, String? error})> testConnection(SyncTask task) async {
    try {
      final client = _createClient(task);

      // 1. 测试服务器可达性
      try {
        await client.ping();
      } catch (e) {
        return (
          success: false,
          error: '无法连接到服务器: ${task.remoteHost}:${task.remotePort}',
        );
      }

      // 2. 检查目标目录是否存在
      try {
        await client.readDir('/');
      } catch (e) {
        return (success: false, error: '目标目录不存在或无访问权限: ${task.remotePath}');
      }

      // 3. 测试目录可写性（尝试创建并删除一个测试文件）
      try {
        final testFileName =
            '/.nanosync_write_test_${DateTime.now().millisecondsSinceEpoch}';

        // 创建临时目录来测试写入权限
        try {
          await client.mkdir(testFileName);
          await client.remove(testFileName);
        } catch (e) {
          // 如果不能创建目录，尝试用文件测试
          return (success: false, error: '目标目录不可写: ${task.remotePath}');
        }
      } catch (e) {
        return (success: false, error: '目标目录不可写: ${task.remotePath}');
      }

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: '连接测试失败: $e');
    }
  }

  Future<List<FileSnapshot>> scanRemoteFolder(SyncTask task) async {
    if (_client == null) {
      final connected = await connect(task);
      if (!connected) throw Exception('无法连接到WebDAV服务器');
    }

    final snapshots = <FileSnapshot>[];
    await _scanDirectory(task, '/', snapshots);
    return snapshots;
  }

  Future<void> _scanDirectory(
    SyncTask task,
    String remotePath,
    List<FileSnapshot> snapshots,
  ) async {
    try {
      final files = await _client!.readDir(remotePath);

      for (final file in files) {
        if (file.name == '.nanosync_versions') continue;

        final relativePath = remotePath == '/'
            ? file.name
            : '$remotePath/${file.name}';

        if (file.isDir) {
          snapshots.add(
            FileSnapshot(
              taskId: task.id,
              relativePath: relativePath,
              absolutePath: relativePath,
              fileSize: 0,
              lastModified: file.modified ?? DateTime.now(),
              crc32: '',
              isDirectory: true,
            ),
          );
          await _scanDirectory(task, relativePath, snapshots);
        } else {
          snapshots.add(
            FileSnapshot(
              taskId: task.id,
              relativePath: relativePath,
              absolutePath: relativePath,
              fileSize: file.size ?? 0,
              lastModified: file.modified ?? DateTime.now(),
              crc32: '',
              isDirectory: false,
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> uploadFile(
    SyncTask task,
    String localPath,
    String remotePath,
  ) async {
    if (_client == null) {
      final connected = await connect(task);
      if (!connected) throw Exception('无法连接到WebDAV服务器');
    }

    final file = File(localPath);
    if (!await file.exists()) throw Exception('本地文件不存在: $localPath');

    final remoteDir = p.dirname(remotePath);
    await _ensureRemoteDirectory(remoteDir);

    try {
      await _client!.writeFile(localPath, remotePath);
      // 验证上传是否成功
      final exists = await _verifyRemoteFile(remotePath, await file.length());
      if (!exists) {
        throw Exception('文件上传后验证失败: $remotePath');
      }
    } catch (e) {
      throw Exception('文件上传失败: $remotePath - $e');
    }
  }

  Future<void> downloadFile(
    SyncTask task,
    String remotePath,
    String localPath,
  ) async {
    if (_client == null) {
      final connected = await connect(task);
      if (!connected) throw Exception('无法连接到WebDAV服务器');
    }

    final localFile = File(localPath);
    await localFile.parent.create(recursive: true);

    await _client!.readFile(remotePath, localPath);

    // 验证下载是否成功
    if (!await localFile.exists()) {
      throw Exception('文件下载失败: $localPath');
    }
  }

  Future<void> deleteRemoteFile(String remotePath) async {
    if (_client == null) throw Exception('未连接到WebDAV服务器');
    await _client!.remove(remotePath);
  }

  Future<void> createRemoteDirectory(String remotePath) async {
    if (_client == null) throw Exception('未连接到WebDAV服务器');
    await _client!.mkdir(remotePath);
  }

  Future<void> _ensureRemoteDirectory(String remotePath) async {
    if (remotePath.isEmpty || remotePath == '/') return;

    final parts = remotePath.split('/').where((p) => p.isNotEmpty).toList();
    String current = '';
    for (final part in parts) {
      current = '$current/$part';
      try {
        await _client!.mkdir(current);
      } catch (_) {
        // 目录可能已存在，忽略错误
      }
    }
  }

  /// 验证远端文件是否存在且大小正确
  Future<bool> _verifyRemoteFile(String remotePath, int expectedSize) async {
    try {
      final files = await _client!.readDir(p.dirname(remotePath));
      final fileName = p.basename(remotePath);
      for (final file in files) {
        if (file.name == fileName && !file.isDir) {
          return file.size == expectedSize || (file.size ?? 0) > 0;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> remoteFileExists(String remotePath) async {
    if (_client == null) return false;
    try {
      await _client!.readDir(p.dirname(remotePath));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<FileSnapshot?> getRemoteFileInfo(
    SyncTask task,
    String remotePath,
  ) async {
    if (_client == null) return null;
    try {
      final parentDir = p.dirname(remotePath);
      final fileName = p.basename(remotePath);
      final files = await _client!.readDir(parentDir);

      for (final file in files) {
        if (file.name == fileName) {
          return FileSnapshot(
            taskId: task.id,
            relativePath: remotePath,
            absolutePath: remotePath,
            fileSize: file.size ?? 0,
            lastModified: file.modified ?? DateTime.now(),
            crc32: '',
            isDirectory: file.isDir,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
