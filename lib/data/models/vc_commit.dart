class VcCommit {
  final String id;
  final String repositoryId;
  final String branchId;
  final String parentCommitId;
  final String secondParentId;
  final String message;
  final String authorName;
  final String authorEmail;
  final DateTime authoredAt;
  final String committerName;
  final String committerEmail;
  final DateTime committedAt;
  final String treeHash;
  final int fileCount;
  final int additions;
  final int deletions;
  final bool isMerge;

  VcCommit({
    String? id,
    required this.repositoryId,
    required this.branchId,
    String? parentCommitId,
    String? secondParentId,
    required this.message,
    String? authorName,
    String? authorEmail,
    DateTime? authoredAt,
    String? committerName,
    String? committerEmail,
    DateTime? committedAt,
    String? treeHash,
    this.fileCount = 0,
    this.additions = 0,
    this.deletions = 0,
    this.isMerge = false,
  }) : id = id ?? _generateId(),
       parentCommitId = parentCommitId ?? '',
       secondParentId = secondParentId ?? '',
       authorName = authorName ?? 'NanoSync User',
       authorEmail = authorEmail ?? 'user@nanosync.local',
       authoredAt = authoredAt ?? DateTime.now(),
       committerName = committerName ?? 'NanoSync User',
       committerEmail = committerEmail ?? 'user@nanosync.local',
       committedAt = committedAt ?? DateTime.now(),
       treeHash = treeHash ?? '';

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcCommit.fromMap(Map<String, dynamic> map) {
    return VcCommit(
      id: map['id'] as String,
      repositoryId: map['repository_id'] as String,
      branchId: map['branch_id'] as String,
      parentCommitId: map['parent_commit_id'] as String? ?? '',
      secondParentId: map['second_parent_id'] as String? ?? '',
      message: map['message'] as String,
      authorName: map['author_name'] as String? ?? 'NanoSync User',
      authorEmail: map['author_email'] as String? ?? 'user@nanosync.local',
      authoredAt: DateTime.parse(map['authored_at'] as String),
      committerName: map['committer_name'] as String? ?? 'NanoSync User',
      committerEmail:
          map['committer_email'] as String? ?? 'user@nanosync.local',
      committedAt: DateTime.parse(map['committed_at'] as String),
      treeHash: map['tree_hash'] as String? ?? '',
      fileCount: map['file_count'] as int? ?? 0,
      additions: map['additions'] as int? ?? 0,
      deletions: map['deletions'] as int? ?? 0,
      isMerge: (map['is_merge'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'branch_id': branchId,
      'parent_commit_id': parentCommitId,
      'second_parent_id': secondParentId,
      'message': message,
      'author_name': authorName,
      'author_email': authorEmail,
      'authored_at': authoredAt.toIso8601String(),
      'committer_name': committerName,
      'committer_email': committerEmail,
      'committed_at': committedAt.toIso8601String(),
      'tree_hash': treeHash,
      'file_count': fileCount,
      'additions': additions,
      'deletions': deletions,
      'is_merge': isMerge ? 1 : 0,
    };
  }

  String get shortId => id.length > 7 ? id.substring(0, 7) : id;

  String get shortMessage {
    final firstLine = message.split('\n').first;
    return firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : firstLine;
  }
}
