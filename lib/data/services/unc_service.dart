import 'dart:io';
import '../models/remote_connection.dart';

/// UNC (Universal Naming Convention) 文件操作服务
/// Windows UNC 路径格式: \\server\share\path
/// 该服务直接使用 Dart IO 操作 UNC 路径，无需额外认证（使用 Windows 当前用户凭据）
class UncService {
  /// 测试 UNC 连接
  /// 检查指定的 UNC 路径是否可访问
  Future<({bool success, String? error})> testConnection({
    required String uncPath,
  }) async {
    try {
      // 标准化 UNC 路径
      final normalizedPath = _normalizeUncPath(uncPath);

      // 检查路径是否存在
      final dir = Directory(normalizedPath);
      if (await dir.exists()) {
        // 尝试列出目录内容以验证读取权限
        await dir.list().first;
        return (success: true, error: null);
      }

      // 如果路径不存在，尝试检查父目录
      // 可能用户只输入了 \\server\share，而没有指定具体路径
      final parent = dir.parent;
      if (await parent.exists()) {
        return (success: true, error: null);
      }

      return (success: false, error: 'UNC 路径不存在或无法访问: $normalizedPath');
    } on FileSystemException catch (e) {
      return (
        success: false,
        error:
            'UNC 连接失败: ${e.message} (OS Error: ${e.osError?.message ?? "unknown"})',
      );
    } catch (e) {
      return (success: false, error: 'UNC 连接失败: $e');
    }
  }

  /// 测试远程连接
  Future<({bool success, String? error})> testRemoteConnection(
    RemoteConnection connection,
  ) async {
    return testConnection(uncPath: connection.host);
  }

  /// 上传文件到 UNC 路径
  Future<void> uploadFile(
    RemoteConnection connection,
    String localPath,
    String remotePath,
  ) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception('本地文件不存在: $localPath');
    }

    // 构建完整的 UNC 路径
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = _joinUncPath(uncBase, remotePath);

    // 确保目标目录存在
    final remoteFile = File(fullRemotePath);
    await remoteFile.parent.create(recursive: true);

    // 复制文件
    await localFile.copy(fullRemotePath);
  }

  /// 从 UNC 路径下载文件
  Future<void> downloadFile(
    RemoteConnection connection,
    String remotePath,
    String localPath,
  ) async {
    // 构建完整的 UNC 路径
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = _joinUncPath(uncBase, remotePath);

    final remoteFile = File(fullRemotePath);
    if (!await remoteFile.exists()) {
      throw Exception('远程文件不存在: $fullRemotePath');
    }

    // 确保本地目录存在
    final localFile = File(localPath);
    await localFile.parent.create(recursive: true);

    // 复制文件
    await remoteFile.copy(localPath);
  }

  /// 删除 UNC 路径上的文件
  Future<void> deleteRemoteFile(
    RemoteConnection connection,
    String remotePath,
  ) async {
    // 构建完整的 UNC 路径
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = _joinUncPath(uncBase, remotePath);

    final remoteFile = File(fullRemotePath);
    if (await remoteFile.exists()) {
      await remoteFile.delete();
    }
  }

  /// 创建远程目录
  Future<void> createDirectory(
    RemoteConnection connection,
    String remotePath,
  ) async {
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = _joinUncPath(uncBase, remotePath);

    final dir = Directory(fullRemotePath);
    await dir.create(recursive: true);
  }

  /// 列出远程目录内容
  Future<List<FileSystemEntity>> listDirectory(
    RemoteConnection connection, {
    String remotePath = '',
  }) async {
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = remotePath.isEmpty
        ? uncBase
        : _joinUncPath(uncBase, remotePath);

    final dir = Directory(fullRemotePath);
    if (!await dir.exists()) {
      throw Exception('远程目录不存在: $fullRemotePath');
    }

    return dir.list().toList();
  }

  /// 检查远程文件/目录是否存在
  Future<bool> exists(RemoteConnection connection, String remotePath) async {
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = _joinUncPath(uncBase, remotePath);

    final entity = FileSystemEntity.typeSync(fullRemotePath);
    return entity != FileSystemEntityType.notFound;
  }

  /// 获取文件信息
  Future<FileStat> stat(RemoteConnection connection, String remotePath) async {
    final uncBase = _normalizeUncPath(connection.host);
    final fullRemotePath = _joinUncPath(uncBase, remotePath);

    final file = File(fullRemotePath);
    return file.stat();
  }

  /// 标准化 UNC 路径
  /// 确保路径以 \\ 开头
  String _normalizeUncPath(String path) {
    final trimmed = path.trim();

    // 如果已经以 \\ 开头，直接返回
    if (trimmed.startsWith('\\\\')) {
      return trimmed;
    }

    // 如果以单个 \ 开头，补充一个
    if (trimmed.startsWith('\\')) {
      return '\\$trimmed';
    }

    // 否则添加 \\ 前缀
    return '\\\\$trimmed';
  }

  /// 连接 UNC 基础路径和相对路径
  String _joinUncPath(String basePath, String relativePath) {
    // 标准化相对路径（将 / 转换为 \）
    final normalizedRelative = relativePath
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'^\\+'), '') // 移除开头的反斜杠
        .replaceAll(RegExp(r'\\+$'), ''); // 移除结尾的反斜杠

    if (normalizedRelative.isEmpty) {
      return basePath;
    }

    // 标准化基础路径
    final normalizedBase = basePath.replaceAll(RegExp(r'\\+$'), '');

    return '$normalizedBase\\$normalizedRelative';
  }

  /// 验证 UNC 路径格式
  static bool isValidUncPath(String path) {
    final trimmed = path.trim();
    // UNC 路径必须以 \\ 开头，后面至少有一个服务器名
    if (!trimmed.startsWith('\\\\')) {
      return false;
    }

    // 提取服务器和共享名部分
    final parts = trimmed.substring(2).split('\\');
    if (parts.isEmpty || parts.first.isEmpty) {
      return false;
    }

    return true;
  }

  /// 从 UNC 路径提取服务器名
  static String? extractServerName(String uncPath) {
    final normalized = uncPath.trim();
    if (!normalized.startsWith('\\\\')) {
      return null;
    }

    final parts = normalized.substring(2).split('\\');
    return parts.isNotEmpty ? parts.first : null;
  }

  /// 从 UNC 路径提取共享名
  static String? extractShareName(String uncPath) {
    final normalized = uncPath.trim();
    if (!normalized.startsWith('\\\\')) {
      return null;
    }

    final parts = normalized.substring(2).split('\\');
    return parts.length > 1 ? parts[1] : null;
  }
}
