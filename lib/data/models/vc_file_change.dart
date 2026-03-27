enum VcChangeType { added, modified, deleted, renamed, copied }

enum VcFileStatus { untracked, modified, staged, committed, ignored }

class VcFileChange {
  final String id;
  final String repositoryId;
  final String commitId;
  final String relativePath;
  final String oldPath;
  final VcChangeType changeType;
  final VcFileStatus status;
  final int oldSize;
  final int newSize;
  final String oldHash;
  final String newHash;
  final int additions;
  final int deletions;
  final bool isBinary;
  final DateTime createdAt;

  VcFileChange({
    String? id,
    required this.repositoryId,
    String? commitId,
    required this.relativePath,
    String? oldPath,
    required this.changeType,
    this.status = VcFileStatus.untracked,
    this.oldSize = 0,
    this.newSize = 0,
    this.oldHash = '',
    this.newHash = '',
    this.additions = 0,
    this.deletions = 0,
    this.isBinary = false,
    DateTime? createdAt,
  }) : id = id ?? _generateId(),
       commitId = commitId ?? '',
       oldPath = oldPath ?? '',
       createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcFileChange.fromMap(Map<String, dynamic> map) {
    return VcFileChange(
      id: map['id'] as String,
      repositoryId: map['repository_id'] as String,
      commitId: map['commit_id'] as String? ?? '',
      relativePath: map['relative_path'] as String,
      oldPath: map['old_path'] as String? ?? '',
      changeType: VcChangeType.values.firstWhere(
        (e) => e.name == (map['change_type'] as String? ?? 'modified'),
        orElse: () => VcChangeType.modified,
      ),
      status: VcFileStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? 'untracked'),
        orElse: () => VcFileStatus.untracked,
      ),
      oldSize: map['old_size'] as int? ?? 0,
      newSize: map['new_size'] as int? ?? 0,
      oldHash: map['old_hash'] as String? ?? '',
      newHash: map['new_hash'] as String? ?? '',
      additions: map['additions'] as int? ?? 0,
      deletions: map['deletions'] as int? ?? 0,
      isBinary: (map['is_binary'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'commit_id': commitId,
      'relative_path': relativePath,
      'old_path': oldPath,
      'change_type': changeType.name,
      'status': status.name,
      'old_size': oldSize,
      'new_size': newSize,
      'old_hash': oldHash,
      'new_hash': newHash,
      'additions': additions,
      'deletions': deletions,
      'is_binary': isBinary ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  VcFileChange copyWith({
    String? commitId,
    VcFileStatus? status,
    int? additions,
    int? deletions,
  }) {
    return VcFileChange(
      id: id,
      repositoryId: repositoryId,
      commitId: commitId ?? this.commitId,
      relativePath: relativePath,
      oldPath: oldPath,
      changeType: changeType,
      status: status ?? this.status,
      oldSize: oldSize,
      newSize: newSize,
      oldHash: oldHash,
      newHash: newHash,
      additions: additions ?? this.additions,
      deletions: deletions ?? this.deletions,
      isBinary: isBinary,
      createdAt: createdAt,
    );
  }

  String get changeTypeIcon {
    switch (changeType) {
      case VcChangeType.added:
        return 'A';
      case VcChangeType.modified:
        return 'M';
      case VcChangeType.deleted:
        return 'D';
      case VcChangeType.renamed:
        return 'R';
      case VcChangeType.copied:
        return 'C';
    }
  }

  String get changeTypeLabel {
    switch (changeType) {
      case VcChangeType.added:
        return '新增';
      case VcChangeType.modified:
        return '修改';
      case VcChangeType.deleted:
        return '删除';
      case VcChangeType.renamed:
        return '重命名';
      case VcChangeType.copied:
        return '复制';
    }
  }
}
