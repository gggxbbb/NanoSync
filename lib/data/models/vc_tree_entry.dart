class VcTreeEntry {
  final String id;
  final String commitId;
  final String relativePath;
  final String fileType;
  final int fileSize;
  final String fileHash;
  final int mode;
  final DateTime createdAt;

  VcTreeEntry({
    String? id,
    required this.commitId,
    required this.relativePath,
    this.fileType = 'file',
    this.fileSize = 0,
    this.fileHash = '',
    this.mode = 420,
    DateTime? createdAt,
  }) : id = id ?? _generateId(),
       createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcTreeEntry.fromMap(Map<String, dynamic> map) {
    return VcTreeEntry(
      id: map['id'] as String,
      commitId: map['commit_id'] as String,
      relativePath: map['relative_path'] as String,
      fileType: map['file_type'] as String? ?? 'file',
      fileSize: map['file_size'] as int? ?? 0,
      fileHash: map['file_hash'] as String? ?? '',
      mode: map['mode'] as int? ?? 420,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'commit_id': commitId,
      'relative_path': relativePath,
      'file_type': fileType,
      'file_size': fileSize,
      'file_hash': fileHash,
      'mode': mode,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
