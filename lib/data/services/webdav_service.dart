import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:webdav_client_plus/webdav_client_plus.dart';
import '../../data/models/sync_task.dart';
import '../../data/models/file_snapshot.dart';

/// WebDAV连接与文件操作服务
class WebDAVService {
  WebdavClient? _client;

  /// 创建带认证的WebDAV客户端
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

  /// 连接WebDAV服务器
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

  /// 断开连接
  void disconnect() {
    _client = null;
  }

  /// 测试连接
  Future<({bool success, String? error})> testConnection(SyncTask task) async {
    try {
      final client = _createClient(task);
      await client.ping();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  /// 扫描远端目录获取文件列表
  Future<List<FileSnapshot>> scanRemoteFolder(SyncTask task) async {
    if (_client == null) {
      final connected = await connect(task);
      if (!connected) throw Exception('无法连接到WebDAV服务器');
    }

    final snapshots = <FileSnapshot>[];
    await _scanDirectory(task, '/', snapshots);
    return snapshots;
  }

  /// 递归扫描远端目录
  Future<void> _scanDirectory(
      SyncTask task, String remotePath, List<FileSnapshot> snapshots) async {
    try {
      final files = await _client!.readDir(remotePath);

      for (final file in files) {
        if (file.name == '.nanosync_versions') continue;

        final relativePath =
            remotePath == '/' ? file.name : '$remotePath/${file.name}';

        if (file.isDir) {
          snapshots.add(FileSnapshot(
            taskId: task.id,
            relativePath: relativePath,
            absolutePath: relativePath,
            fileSize: 0,
            lastModified: file.modified ?? DateTime.now(),
            crc32: '',
            isDirectory: true,
          ));
          await _scanDirectory(task, relativePath, snapshots);
        } else {
          snapshots.add(FileSnapshot(
            taskId: task.id,
            relativePath: relativePath,
            absolutePath: relativePath,
            fileSize: file.size ?? 0,
            lastModified: file.modified ?? DateTime.now(),
            crc32: '',
            isDirectory: false,
          ));
        }
      }
    } catch (_) {}
  }

  /// 上传文件到远端
  Future<void> uploadFile(
      SyncTask task, String localPath, String remotePath) async {
    if (_client == null) {
      final connected = await connect(task);
      if (!connected) throw Exception('无法连接到WebDAV服务器');
    }

    final file = File(localPath);
    if (!await file.exists()) throw Exception('本地文件不存在: $localPath');

    final remoteDir = p.dirname(remotePath);
    await _ensureRemoteDirectory(remoteDir);

    await _client!.writeFile(localPath, remotePath);
  }

  /// 从远端下载文件
  Future<void> downloadFile(
      SyncTask task, String remotePath, String localPath) async {
    if (_client == null) {
      final connected = await connect(task);
      if (!connected) throw Exception('无法连接到WebDAV服务器');
    }

    final localFile = File(localPath);
    await localFile.parent.create(recursive: true);

    await _client!.readFile(remotePath, localPath);
  }

  /// 删除远端文件
  Future<void> deleteRemoteFile(String remotePath) async {
    if (_client == null) throw Exception('未连接到WebDAV服务器');
    await _client!.remove(remotePath);
  }

  /// 创建远端目录
  Future<void> createRemoteDirectory(String remotePath) async {
    if (_client == null) throw Exception('未连接到WebDAV服务器');
    await _client!.mkdir(remotePath);
  }

  /// 确保远端目录存在
  Future<void> _ensureRemoteDirectory(String remotePath) async {
    if (remotePath.isEmpty || remotePath == '/') return;

    final parts = remotePath.split('/').where((p) => p.isNotEmpty).toList();
    String current = '';
    for (final part in parts) {
      current = '$current/$part';
      try {
        await _client!.mkdir(current);
      } catch (_) {}
    }
  }

  /// 检查远端文件是否存在
  Future<bool> remoteFileExists(String remotePath) async {
    if (_client == null) return false;
    try {
      await _client!.readDir(p.dirname(remotePath));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取远端文件信息
  Future<FileSnapshot?> getRemoteFileInfo(
      SyncTask task, String remotePath) async {
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
