import '../database/database_helper.dart';
import '../models/remote_connection.dart';
import 'smb_service.dart';
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
  final WebDAVService _webdav;

  RemoteConnectionManager._({
    DatabaseHelper? db,
    SmbService? smb,
    WebDAVService? webdav,
  }) : _db = db ?? DatabaseHelper.instance,
       _smb = smb ?? SmbService(),
       _webdav = webdav ?? WebDAVService();

  static RemoteConnectionManager get instance {
    _instance ??= RemoteConnectionManager._();
    return _instance!;
  }

  Future<RemoteConnection> addConnection(RemoteConnection connection) async {
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
      return ConnectionTestResult(success: false, error: e.toString());
    }
  }

  Future<void> bindToRepository({
    required String repositoryId,
    required String connectionName,
    required String remotePath,
    bool isDefault = false,
  }) async {
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
}
