import '../../core/constants/enums.dart';

/// 文件快照数据模型
class FileSnapshot {
  final String id;
  final String taskId;
  final String relativePath;
  final String absolutePath;
  final int fileSize;
  final DateTime lastModified;
  final String crc32;
  final String sha256;
  final bool isDirectory;
  final DateTime createdAt;

  FileSnapshot({
    String? id,
    required this.taskId,
    required this.relativePath,
    required this.absolutePath,
    required this.fileSize,
    required this.lastModified,
    required this.crc32,
    this.sha256 = '',
    this.isDirectory = false,
    DateTime? createdAt,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        (DateTime.now().microsecond % 1000).toRadixString(36);
  }

  factory FileSnapshot.fromMap(Map<String, dynamic> map) {
    return FileSnapshot(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      relativePath: map['relative_path'] as String,
      absolutePath: map['absolute_path'] as String,
      fileSize: map['file_size'] as int,
      lastModified: DateTime.parse(map['last_modified'] as String),
      crc32: map['crc32'] as String? ?? '',
      sha256: map['sha256'] as String? ?? '',
      isDirectory: (map['is_directory'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'relative_path': relativePath,
      'absolute_path': absolutePath,
      'file_size': fileSize,
      'last_modified': lastModified.toIso8601String(),
      'crc32': crc32,
      'sha256': sha256,
      'is_directory': isDirectory ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 判断两个快照是否相同（文件未变更）
  bool isSameAs(FileSnapshot other) {
    if (fileSize != other.fileSize) return false;
    if (lastModified != other.lastModified) return false;
    if (crc32.isNotEmpty && other.crc32.isNotEmpty && crc32 != other.crc32) {
      return false;
    }
    return true;
  }
}

/// 文件变更记录模型
class FileChange {
  final String taskId;
  final String relativePath;
  final String localPath;
  final String remotePath;
  final ChangeType changeType;
  final SyncOperation operation;
  final int fileSize;
  final String crc32;
  final String? oldRelativePath;
  final FileSnapshot? localSnapshot;
  final FileSnapshot? remoteSnapshot;

  FileChange({
    required this.taskId,
    required this.relativePath,
    required this.localPath,
    required this.remotePath,
    required this.changeType,
    required this.operation,
    this.fileSize = 0,
    this.crc32 = '',
    this.oldRelativePath,
    this.localSnapshot,
    this.remoteSnapshot,
  });

  bool get isConflict =>
      localSnapshot != null &&
      remoteSnapshot != null &&
      changeType == ChangeType.modified;
}
