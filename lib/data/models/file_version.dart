/// 文件版本记录模型
class FileVersion {
  final String id;
  final String taskId;
  final String originalPath;
  final String versionPath;
  final String versionName;
  final int versionNumber;
  final int fileSize;
  final String crc32;
  final String operationType;
  final DateTime createdAt;

  FileVersion({
    String? id,
    required this.taskId,
    required this.originalPath,
    required this.versionPath,
    required this.versionName,
    required this.versionNumber,
    required this.fileSize,
    this.crc32 = '',
    this.operationType = 'modify',
    DateTime? createdAt,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        (DateTime.now().microsecond % 1000).toRadixString(36);
  }

  factory FileVersion.fromMap(Map<String, dynamic> map) {
    return FileVersion(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      originalPath: map['original_path'] as String,
      versionPath: map['version_path'] as String,
      versionName: map['version_name'] as String,
      versionNumber: map['version_number'] as int,
      fileSize: map['file_size'] as int,
      crc32: map['crc32'] as String? ?? '',
      operationType: map['operation_type'] as String? ?? 'modify',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'original_path': originalPath,
      'version_path': versionPath,
      'version_name': versionName,
      'version_number': versionNumber,
      'file_size': fileSize,
      'crc32': crc32,
      'operation_type': operationType,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 生成版本文件名
  static String generateVersionName(
      String originalFileName, int versionNumber, DateTime time) {
    final timestamp = '${time.year}${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}_'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}'
        '${time.second.toString().padLeft(2, '0')}';
    final ext = originalFileName.contains('.')
        ? '.${originalFileName.split('.').last}'
        : '';
    final baseName = originalFileName.contains('.')
        ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
        : originalFileName;
    return '${timestamp}_v${versionNumber}_$baseName$ext';
  }

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
