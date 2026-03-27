import '../../core/constants/app_constants.dart';

class RepositoryLocalSettings {
  final String repositoryId;
  final int maxVersions;
  final int maxVersionDays;
  final int maxVersionSizeGB;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RepositoryLocalSettings({
    required this.repositoryId,
    this.maxVersions = AppConstants.defaultMaxVersions,
    this.maxVersionDays = AppConstants.defaultMaxVersionDays,
    this.maxVersionSizeGB = AppConstants.defaultMaxVersionSizeGB,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RepositoryLocalSettings.createDefault(String repositoryId) {
    final now = DateTime.now();
    return RepositoryLocalSettings(
      repositoryId: repositoryId,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory RepositoryLocalSettings.fromMap(Map<String, dynamic> map) {
    return RepositoryLocalSettings(
      repositoryId: map['repository_id'] as String,
      maxVersions:
          (map['max_versions'] as int?) ?? AppConstants.defaultMaxVersions,
      maxVersionDays:
          (map['max_version_days'] as int?) ??
          AppConstants.defaultMaxVersionDays,
      maxVersionSizeGB:
          (map['max_version_size_gb'] as int?) ??
          AppConstants.defaultMaxVersionSizeGB,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'repository_id': repositoryId,
      'max_versions': maxVersions,
      'max_version_days': maxVersionDays,
      'max_version_size_gb': maxVersionSizeGB,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  RepositoryLocalSettings copyWith({
    int? maxVersions,
    int? maxVersionDays,
    int? maxVersionSizeGB,
    DateTime? updatedAt,
  }) {
    return RepositoryLocalSettings(
      repositoryId: repositoryId,
      maxVersions: maxVersions ?? this.maxVersions,
      maxVersionDays: maxVersionDays ?? this.maxVersionDays,
      maxVersionSizeGB: maxVersionSizeGB ?? this.maxVersionSizeGB,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
