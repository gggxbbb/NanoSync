class VcStagingEntry {
  final String id;
  final String repositoryId;
  final String relativePath;
  final String oldPath;
  final String changeType;
  final int oldSize;
  final int newSize;
  final String oldHash;
  final String newHash;
  final bool isStaged;
  final DateTime createdAt;

  VcStagingEntry({
    String? id,
    required this.repositoryId,
    required this.relativePath,
    String? oldPath,
    this.changeType = 'modified',
    this.oldSize = 0,
    this.newSize = 0,
    this.oldHash = '',
    this.newHash = '',
    this.isStaged = false,
    DateTime? createdAt,
  }) : id = id ?? _generateId(),
       oldPath = oldPath ?? '',
       createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcStagingEntry.fromMap(Map<String, dynamic> map) {
    return VcStagingEntry(
      id: map['id'] as String,
      repositoryId: map['repository_id'] as String,
      relativePath: map['relative_path'] as String,
      oldPath: map['old_path'] as String? ?? '',
      changeType: map['change_type'] as String? ?? 'modified',
      oldSize: map['old_size'] as int? ?? 0,
      newSize: map['new_size'] as int? ?? 0,
      oldHash: map['old_hash'] as String? ?? '',
      newHash: map['new_hash'] as String? ?? '',
      isStaged: (map['is_staged'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'relative_path': relativePath,
      'old_path': oldPath,
      'change_type': changeType,
      'old_size': oldSize,
      'new_size': newSize,
      'old_hash': oldHash,
      'new_hash': newHash,
      'is_staged': isStaged ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  VcStagingEntry copyWith({bool? isStaged, String? changeType}) {
    return VcStagingEntry(
      id: id,
      repositoryId: repositoryId,
      relativePath: relativePath,
      oldPath: oldPath,
      changeType: changeType ?? this.changeType,
      oldSize: oldSize,
      newSize: newSize,
      oldHash: oldHash,
      newHash: newHash,
      isStaged: isStaged ?? this.isStaged,
      createdAt: createdAt,
    );
  }
}
