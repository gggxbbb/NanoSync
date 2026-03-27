import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';
import '../models/remote_directory_item.dart';
import '../models/remote_connection.dart';

/// SMB connection and file operation service.
class SmbService {
  SmbConnect? _client;

  Future<bool> connect(
    RemoteConnection connection, {
    bool forceReconnect = false,
  }) async {
    if (!forceReconnect && _client != null) {
      return true;
    }

    await disconnect();

    if (connection.port != 445) {
      throw Exception('SMB 当前仅支持 445 端口');
    }

    final username = _normalizeUsername(connection.username);

    _client = await SmbConnect.connectAuth(
      host: connection.host,
      username: username,
      password: connection.password,
      domain: '',
    );

    return true;
  }

  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    if (client != null) {
      await client.close();
    }
  }

  Future<({bool success, String? error})> testConnection({
    required String host,
    required int port,
    required String username,
    required String password,
    bool strictCredentialCheck = false,
  }) async {
    if (port != 445) {
      return (success: false, error: 'SMB 当前仅支持 445 端口');
    }

    SmbConnect? conn;
    try {
      conn = await SmbConnect.connectAuth(
        host: host,
        username: _normalizeUsername(username),
        password: password,
        domain: '',
      );

      // listShares forces authenticated tree/session operations.
      final shares = await conn.listShares();
      if (strictCredentialCheck && shares.isEmpty) {
        return (success: false, error: '认证成功，但未发现可访问共享');
      }

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'SMB 认证失败: $e');
    } finally {
      if (conn != null) {
        await conn.close();
      }
    }
  }

  Future<void> uploadFile(
    RemoteConnection connection,
    String localPath,
    String remotePath,
  ) async {
    await _ensureConnected(connection);

    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception('本地文件不存在: $localPath');
    }

    final normalizedRemotePath = _requireSharePath(remotePath);
    final remoteDir = p.posix.dirname(normalizedRemotePath);
    await _ensureRemoteDirectory(remoteDir);

    var remoteFile = await _client!.file(normalizedRemotePath);
    if (!remoteFile.isExists) {
      remoteFile = await _client!.createFile(normalizedRemotePath);
    }

    final sink = await _client!.openWrite(remoteFile, append: false);
    await sink.addStream(localFile.openRead());
    await sink.flush();
    await sink.close();
  }

  Future<void> downloadFile(
    RemoteConnection connection,
    String remotePath,
    String localPath,
  ) async {
    await _ensureConnected(connection);

    final normalizedRemotePath = _requireSharePath(remotePath);
    final remoteFile = await _client!.file(normalizedRemotePath);

    if (!remoteFile.isExists || remoteFile.isDirectory()) {
      throw Exception('远端文件不存在: $normalizedRemotePath');
    }

    final localFile = File(localPath);
    await localFile.parent.create(recursive: true);

    final stream = await _client!.openRead(remoteFile);
    final sink = localFile.openWrite();
    await sink.addStream(stream);
    await sink.flush();
    await sink.close();
  }

  Future<void> deleteRemoteFile(
    RemoteConnection connection,
    String remotePath,
  ) async {
    await _ensureConnected(connection);

    final normalizedRemotePath = _requireSharePath(remotePath);
    final remote = await _client!.file(normalizedRemotePath);
    if (!remote.isExists) {
      return;
    }

    await _client!.delete(remote);
  }

  Future<List<RemoteDirectoryItem>> listDirectories(
    RemoteConnection connection, {
    String remotePath = '/',
  }) async {
    await _ensureConnected(connection);

    final normalized = _normalizeRemotePath(remotePath);
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();

    // SMB root: list shares as first-level directories.
    if (segments.isEmpty) {
      final shares = await _client!.listShares();
      final items = <RemoteDirectoryItem>[];
      for (final share in shares) {
        final name = _extractShareName(share);
        if (name.isEmpty) continue;
        items.add(RemoteDirectoryItem(name: name, path: '/$name'));
      }
      items.sort((a, b) => a.name.compareTo(b.name));
      return items;
    }

    // smb_connect does not currently expose a stable directory-list API across versions.
    // Keep picker usable by allowing share selection and manual deeper input.
    return const <RemoteDirectoryItem>[];
  }

  Future<void> createDirectory(
    RemoteConnection connection,
    String remotePath,
  ) async {
    await _ensureConnected(connection);
    final normalizedRemotePath = _requireSharePath(remotePath);
    try {
      await _client!.createFolder(normalizedRemotePath);
    } catch (_) {
      final existing = await _client!.file(normalizedRemotePath);
      if (!existing.isExists || !existing.isDirectory()) {
        rethrow;
      }
    }
  }

  Future<void> _ensureRemoteDirectory(String remotePath) async {
    final normalized = _requireSharePath(remotePath);
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();

    if (segments.length <= 1) {
      return;
    }

    var current = '/${segments.first}';
    for (var i = 1; i < segments.length; i++) {
      current = '$current/${segments[i]}';
      try {
        await _client!.createFolder(current);
      } catch (_) {
        final existing = await _client!.file(current);
        if (!existing.isExists || !existing.isDirectory()) {
          rethrow;
        }
      }
    }
  }

  Future<void> _ensureConnected(RemoteConnection connection) async {
    if (_client != null) {
      return;
    }
    await connect(connection);
  }

  String _normalizeUsername(String username) {
    final trimmed = username.trim();
    return trimmed.isEmpty ? 'guest' : trimmed;
  }

  String _requireSharePath(String rawPath) {
    final normalized = _normalizeRemotePath(rawPath);
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();

    if (segments.isEmpty) {
      throw Exception('SMB 路径必须包含共享名，例如 /public 或 /public/folder');
    }

    return '/${segments.join('/')}';
  }

  String _normalizeRemotePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '/';
    }

    final slashNormalized = trimmed.replaceAll('\\', '/');
    final prefixed = slashNormalized.startsWith('/')
        ? slashNormalized
        : '/$slashNormalized';

    var collapsed = prefixed.replaceAll(RegExp(r'/+'), '/');
    if (collapsed.length > 1 && collapsed.endsWith('/')) {
      collapsed = collapsed.substring(0, collapsed.length - 1);
    }
    return collapsed;
  }

  String _extractShareName(dynamic share) {
    if (share is String) {
      return share;
    }
    try {
      final dynamicName = share.name;
      if (dynamicName is String) {
        return dynamicName;
      }
    } catch (_) {}
    final asString = share.toString();
    if (asString.startsWith('Instance of')) {
      return '';
    }
    return asString;
  }
}
