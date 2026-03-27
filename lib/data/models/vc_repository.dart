class VcRepository {
  final String id;
  final String name;
  final String localPath;
  final String currentBranchId;
  final String headCommitId;
  final bool isInitialized;
  final DateTime createdAt;
  final DateTime updatedAt;

  VcRepository({
    String? id,
    required this.name,
    required this.localPath,
    String? currentBranchId,
    String? headCommitId,
    this.isInitialized = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _generateId(),
       currentBranchId = currentBranchId ?? '',
       headCommitId = headCommitId ?? '',
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcRepository.fromMap(Map<String, dynamic> map) {
    return VcRepository(
      id: map['id'] as String,
      name: map['name'] as String,
      localPath: map['local_path'] as String,
      currentBranchId: map['current_branch_id'] as String? ?? '',
      headCommitId: map['head_commit_id'] as String? ?? '',
      isInitialized: (map['is_initialized'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'local_path': localPath,
      'current_branch_id': currentBranchId,
      'head_commit_id': headCommitId,
      'is_initialized': isInitialized ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  VcRepository copyWith({
    String? name,
    String? localPath,
    String? currentBranchId,
    String? headCommitId,
    bool? isInitialized,
    DateTime? updatedAt,
  }) {
    return VcRepository(
      id: id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      currentBranchId: currentBranchId ?? this.currentBranchId,
      headCommitId: headCommitId ?? this.headCommitId,
      isInitialized: isInitialized ?? this.isInitialized,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
