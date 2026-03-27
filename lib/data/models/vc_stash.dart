class VcStash {
  final String id;
  final String repositoryId;
  final String branchId;
  final String message;
  final String commitId;
  final int fileCount;
  final DateTime createdAt;

  VcStash({
    String? id,
    required this.repositoryId,
    String? branchId,
    required this.message,
    String? commitId,
    this.fileCount = 0,
    DateTime? createdAt,
  }) : id = id ?? _generateId(),
       branchId = branchId ?? '',
       commitId = commitId ?? '',
       createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcStash.fromMap(Map<String, dynamic> map) {
    return VcStash(
      id: map['id'] as String,
      repositoryId: map['repository_id'] as String,
      branchId: map['branch_id'] as String? ?? '',
      message: map['message'] as String,
      commitId: map['commit_id'] as String? ?? '',
      fileCount: map['file_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'branch_id': branchId,
      'message': message,
      'commit_id': commitId,
      'file_count': fileCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get shortId => id.length > 7 ? id.substring(0, 7) : id;
}
