class VcBranch {
  final String id;
  final String repositoryId;
  final String name;
  final String commitId;
  final bool isDefault;
  final DateTime createdAt;

  VcBranch({
    String? id,
    required this.repositoryId,
    required this.name,
    String? commitId,
    this.isDefault = false,
    DateTime? createdAt,
  }) : id = id ?? _generateId(),
       commitId = commitId ?? '',
       createdAt = createdAt ?? DateTime.now();

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  factory VcBranch.fromMap(Map<String, dynamic> map) {
    return VcBranch(
      id: map['id'] as String,
      repositoryId: map['repository_id'] as String,
      name: map['name'] as String,
      commitId: map['commit_id'] as String? ?? '',
      isDefault: (map['is_default'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'name': name,
      'commit_id': commitId,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  VcBranch copyWith({String? name, String? commitId, bool? isDefault}) {
    return VcBranch(
      id: id,
      repositoryId: repositoryId,
      name: name ?? this.name,
      commitId: commitId ?? this.commitId,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
    );
  }
}
