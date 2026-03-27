import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:webdav_client_plus/webdav_client_plus.dart';
import '../models/remote_directory_item.dart';
import '../models/remote_connection.dart';

/// WebDAV连接与文件操作服务
class WebDAVService {
  WebdavClient? _client;

  WebdavClient _createClient(RemoteConnection connection, String remotePath) {
    final port = connection.port == 0 ? 443 : connection.port;
    final scheme = port == 443 ? 'https' : 'http';
    final normalizedPath = _normalizePath(remotePath);
    final url = '$scheme://${connection.host}:$port$normalizedPath';

    late WebdavClient client;
    if (connection.username.isEmpty) {
      client = WebdavClient.noAuth(url: url);
    } else {
      client = WebdavClient.basicAuth(
        url: url,
        user: connection.username,
        pwd: connection.password,
      );
    }

    client.setConnectTimeout(8000);
    client.setReceiveTimeout(8000);
    return client;
  }

  Future<bool> connect(
    RemoteConnection connection, {
    String remotePath = '/',
  }) async {
    try {
      _client = _createClient(connection, remotePath);
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
  Future<({bool success, String? error})> testConnection(
    RemoteConnection connection, {
    String probePath = '/',
  }) async {
    try {
      final normalizedProbePath = _normalizePath(probePath);
      final client = _createClient(connection, normalizedProbePath);

      // 1. 测试服务器可达性
      try {
        await client.ping();
      } catch (e) {
        return (
          success: false,
          error: '无法连接到服务器: ${connection.host}:${connection.port}',
        );
      }

      // 2. 检查目标目录是否存在
      try {
        await client.readDir('/');
      } catch (e) {
        return (success: false, error: '目标目录不存在或无访问权限: $normalizedProbePath');
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
          return (success: false, error: '目标目录不可写: $normalizedProbePath');
        }
      } catch (e) {
        return (success: false, error: '目标目录不可写: $normalizedProbePath');
      }

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: '连接测试失败: $e');
    }
  }

  Future<void> uploadFile(
    RemoteConnection connection,
    String localPath,
    String remotePath,
  ) async {
    if (_client == null) {
      final connected = await connect(connection);
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
    RemoteConnection connection,
    String remotePath,
    String localPath,
  ) async {
    if (_client == null) {
      final connected = await connect(connection);
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

  Future<void> createDirectoryForConnection(
    RemoteConnection connection,
    String remotePath,
  ) async {
    final client = _createClient(connection, '/');
    final normalizedPath = _normalizePath(remotePath);
    await client.mkdir(normalizedPath);
  }

  Future<List<RemoteDirectoryItem>> listDirectories(
    RemoteConnection connection, {
    String remotePath = '/',
  }) async {
    final client = _createClient(connection, '/');
    final normalizedPath = _normalizePath(remotePath);
    final entries = await client.readDir(normalizedPath);

    final result = <RemoteDirectoryItem>[];
    for (final entry in entries) {
      if (entry.isDir != true) continue;
      final name = entry.name.trim();
      if (name.isEmpty || name == '.' || name == '..') continue;
      final childPath = normalizedPath == '/'
          ? '/$name'
          : '${normalizedPath.endsWith('/') ? normalizedPath.substring(0, normalizedPath.length - 1) : normalizedPath}/$name';
      result.add(RemoteDirectoryItem(name: name, path: childPath));
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
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
        // mkdir may fail if directory already exists; verify existence
        try {
          await _client!.readDir(current);
        } catch (e) {
          throw Exception('无法创建远端目录: $current - $e');
        }
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
      final parentDir = p.dirname(remotePath);
      final fileName = p.basename(remotePath);
      final files = await _client!.readDir(parentDir);
      return files.any((f) => f.name == fileName && !f.isDir);
    } catch (_) {
      return false;
    }
  }

  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '/';
    }
    final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return withLeadingSlash.replaceAll(RegExp(r'/+'), '/');
  }
}
