import 'dart:io';

import '../database/database_helper.dart';
import '../models/remote_directory_item.dart';
import '../models/remote_connection.dart';
import '../../core/constants/enums.dart';
import 'app_log_service.dart';
import 'smb_service.dart';
import 'unc_service.dart';
import 'webdav_service.dart';

class ConnectionTestResult {
  final bool success;
  final String? error;

  const ConnectionTestResult({required this.success, this.error});
}

class RemoteConnectionManager {
  static RemoteConnectionManager? _instance;
  final DatabaseHelper _db;
  final SmbService _smb;
  final UncService _unc;
  final WebDAVService _webdav;
  final AppLogService _appLog;

  RemoteConnectionManager._({
    DatabaseHelper? db,
    SmbService? smb,
    UncService? unc,
    WebDAVService? webdav,
    AppLogService? appLog,
  }) : _db = db ?? DatabaseHelper.instance,
       _smb = smb ?? SmbService(),
       _unc = unc ?? UncService(),
       _webdav = webdav ?? WebDAVService(),
       _appLog = appLog ?? AppLogService.instance;

  static RemoteConnectionManager get instance {
    _instance ??= RemoteConnectionManager._();
    return _instance!;
  }

  Future<RemoteConnection> addConnection(RemoteConnection connection) async {
    await _appLog.info(
      category: 'remote',
      message: 'Add remote connection',
      source: 'RemoteConnectionManager.addConnection',
      context: {
        'name': connection.name,
        'protocol': connection.protocol.value,
        'host': connection.host,
        'port': connection.port,
      },
    );

    final existing = await _db.getRemoteConnectionByName(connection.name);
    if (existing != null) {
      throw Exception(
        'Connection with name "${connection.name}" already exists',
      );
    }

    await _db.insertRemoteConnection(connection.toMap());
    return connection;
  }

  Future<void> updateConnection(RemoteConnection connection) async {
    await _appLog.info(
      category: 'remote',
      message: 'Update remote connection',
      source: 'RemoteConnectionManager.updateConnection',
      context: {'id': connection.id, 'name': connection.name},
    );

    final existing = await _db.getRemoteConnection(connection.id);
    if (existing == null) {
      throw Exception('Connection not found');
    }

    final byName = await _db.getRemoteConnectionByName(connection.name);
    if (byName != null && (byName['id'] as String) != connection.id) {
      throw Exception(
        'Connection with name "${connection.name}" already exists',
      );
    }

    await _db.updateRemoteConnection(connection.id, connection.toMap());
  }

  Future<void> removeConnection(String connectionId) async {
    await _appLog.warning(
      category: 'remote',
      message: 'Remove remote connection',
      source: 'RemoteConnectionManager.removeConnection',
      context: {'id': connectionId},
    );
    await _db.deleteRemoteConnection(connectionId);
  }

  Future<RemoteConnection?> getConnection(String connectionId) async {
    final map = await _db.getRemoteConnection(connectionId);
    return map != null ? RemoteConnection.fromMap(map) : null;
  }

  Future<RemoteConnection?> getConnectionByName(String name) async {
    final map = await _db.getRemoteConnectionByName(name);
    return map != null ? RemoteConnection.fromMap(map) : null;
  }

  Future<List<RemoteConnection>> listConnections() async {
    final maps = await _db.getAllRemoteConnections();
    return maps.map((m) => RemoteConnection.fromMap(m)).toList();
  }

  Future<ConnectionTestResult> testConnection(String connectionId) async {
    final conn = await getConnection(connectionId);
    if (conn == null) {
      return const ConnectionTestResult(
        success: false,
        error: 'Connection not found',
      );
    }

    return _testConnectionInternal(conn);
  }

  Future<ConnectionTestResult> testConnectionDirect(
    RemoteConnection connection,
  ) async {
    return _testConnectionInternal(connection);
  }

  Future<ConnectionTestResult> _testConnectionInternal(
    RemoteConnection conn,
  ) async {
    await _appLog.debug(
      category: 'remote',
      message: 'Test remote connection',
      source: 'RemoteConnectionManager._testConnectionInternal',
      context: {
        'name': conn.name,
        'protocol': conn.protocol.value,
        'host': conn.host,
        'port': conn.port,
      },
    );

    try {
      if (conn.protocol.value == 'smb') {
        final result = await _smb.testConnection(
          host: conn.host,
          port: conn.port,
          username: conn.username,
          password: conn.password,
          strictCredentialCheck: true,
        );
        return ConnectionTestResult(
          success: result.success,
          error: result.error,
        );
      } else if (conn.protocol.value == 'unc') {
        final result = await _unc.testConnection(uncPath: conn.host);
        return ConnectionTestResult(
          success: result.success,
          error: result.error,
        );
      } else if (conn.protocol.value == 'webdav') {
        final result = await _webdav.testConnection(conn);
        return ConnectionTestResult(
          success: result.success,
          error: result.error,
        );
      } else {
        return const ConnectionTestResult(
          success: false,
          error: 'Unsupported protocol',
        );
      }
    } catch (e) {
      await _appLog.error(
        category: 'remote',
        message: 'Test remote connection failed',
        source: 'RemoteConnectionManager._testConnectionInternal',
        details: e.toString(),
        context: {'name': conn.name, 'protocol': conn.protocol.value},
      );
      return ConnectionTestResult(success: false, error: e.toString());
    }
  }

  Future<void> bindToRepository({
    required String repositoryId,
    required String connectionName,
    required String remotePath,
    bool isDefault = false,
  }) async {
    await _appLog.info(
      category: 'remote',
      message: 'Bind remote to repository',
      source: 'RemoteConnectionManager.bindToRepository',
      repositoryId: repositoryId,
      context: {
        'connectionName': connectionName,
        'remotePath': remotePath,
        'isDefault': isDefault,
      },
    );

    final conn = await _db.getRemoteConnectionByName(connectionName);
    if (conn == null) {
      throw Exception('Connection not found: $connectionName');
    }

    final existing = await _db.getRepositoryRemoteByName(
      repositoryId,
      connectionName,
    );
    if (existing != null) {
      await _db.updateRepositoryRemote(existing['id'] as String, {
        'remote_path': remotePath,
        'is_default': isDefault ? 1 : 0,
      });
      if (isDefault) {
        // Keep default remote unique within a repository.
        await _db.setDefaultRepositoryRemote(repositoryId, connectionName);
      }
      return;
    }

    if (isDefault) {
      await _db.setDefaultRepositoryRemote(repositoryId, connectionName);
    }

    await _db.insertRepositoryRemote({
      'id': DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      'repository_id': repositoryId,
      'remote_name': connectionName,
      'remote_path': remotePath,
      'is_default': isDefault ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> unbindFromRepository({
    required String repositoryId,
    required String connectionName,
  }) async {
    await _appLog.warning(
      category: 'remote',
      message: 'Unbind remote from repository',
      source: 'RemoteConnectionManager.unbindFromRepository',
      repositoryId: repositoryId,
      context: {'connectionName': connectionName},
    );

    final repoRemote = await _db.getRepositoryRemoteByName(
      repositoryId,
      connectionName,
    );
    if (repoRemote != null) {
      await _db.deleteRepositoryRemote(repoRemote['id'] as String);
    }
  }

  Future<void> setDefaultRemote({
    required String repositoryId,
    required String connectionName,
  }) async {
    await _appLog.info(
      category: 'remote',
      message: 'Set default remote',
      source: 'RemoteConnectionManager.setDefaultRemote',
      repositoryId: repositoryId,
      context: {'connectionName': connectionName},
    );
    await _db.setDefaultRepositoryRemote(repositoryId, connectionName);
  }

  Future<List<Map<String, dynamic>>> getRepositoryRemotes(
    String repositoryId,
  ) async {
    final repoRemotes = await _db.getRepositoryRemotes(repositoryId);
    final result = <Map<String, dynamic>>[];

    for (final rr in repoRemotes) {
      final conn = await _db.getRemoteConnectionByName(
        rr['remote_name'] as String,
      );
      result.add({...rr, 'connection': conn});
    }

    return result;
  }

  Future<Map<String, dynamic>?> getDefaultRepositoryRemote(
    String repositoryId,
  ) async {
    final repoRemote = await _db.getDefaultRepositoryRemote(repositoryId);
    if (repoRemote == null) return null;

    final conn = await _db.getRemoteConnectionByName(
      repoRemote['remote_name'] as String,
    );
    return {...repoRemote, 'connection': conn};
  }

  bool supportsRemotePathBrowser(RemoteConnection connection) {
    return connection.protocol == RemoteProtocol.webdav ||
        connection.protocol == RemoteProtocol.unc ||
        connection.protocol == RemoteProtocol.smb;
  }

  Future<List<RemoteDirectoryItem>> listRemoteDirectories({
    required String connectionName,
    required String remotePath,
  }) async {
    await _appLog.debug(
      category: 'remote',
      message: 'List remote directories',
      source: 'RemoteConnectionManager.listRemoteDirectories',
      context: {'connectionName': connectionName, 'remotePath': remotePath},
    );

    final connection = await getConnectionByName(connectionName);
    if (connection == null) {
      throw Exception('Connection not found: $connectionName');
    }

    switch (connection.protocol) {
      case RemoteProtocol.webdav:
        return _webdav.listDirectories(connection, remotePath: remotePath);
      case RemoteProtocol.unc:
        final entries = await _unc.listDirectory(
          connection,
          remotePath: remotePath,
        );
        final items = <RemoteDirectoryItem>[];
        for (final entry in entries) {
          final stat = await entry.stat();
          if (stat.type != FileSystemEntityType.directory) {
            continue;
          }
          final name = entry.uri.pathSegments.isNotEmpty
              ? entry.uri.pathSegments.lastWhere(
                  (s) => s.isNotEmpty,
                  orElse: () => '',
                )
              : '';
          if (name.isEmpty) {
            continue;
          }
          final normalizedPath = _joinRemotePath(remotePath, name);
          items.add(RemoteDirectoryItem(name: name, path: normalizedPath));
        }
        items.sort((a, b) => a.name.compareTo(b.name));
        return items;
      case RemoteProtocol.smb:
        return _smb.listDirectories(connection, remotePath: remotePath);
    }
  }

  Future<void> createRemoteDirectory({
    required String connectionName,
    required String remotePath,
  }) async {
    await _appLog.info(
      category: 'remote',
      message: 'Create remote directory',
      source: 'RemoteConnectionManager.createRemoteDirectory',
      context: {'connectionName': connectionName, 'remotePath': remotePath},
    );

    final connection = await getConnectionByName(connectionName);
    if (connection == null) {
      throw Exception('Connection not found: $connectionName');
    }

    switch (connection.protocol) {
      case RemoteProtocol.webdav:
        await _webdav.createDirectoryForConnection(connection, remotePath);
        break;
      case RemoteProtocol.unc:
        await _unc.createDirectory(connection, remotePath);
        break;
      case RemoteProtocol.smb:
        await _smb.createDirectory(connection, remotePath);
        break;
    }
  }

  String _joinRemotePath(String base, String folderName) {
    final normalizedBase = base.trim().isEmpty ? '/' : base.trim();
    final slashBase = normalizedBase.replaceAll('\\', '/');
    final compactBase = slashBase.endsWith('/')
        ? slashBase.substring(0, slashBase.length - 1)
        : slashBase;
    if (compactBase.isEmpty || compactBase == '/') {
      return '/$folderName';
    }
    return '$compactBase/$folderName';
  }
}
