class HistoryConfig {
  final int maxCount;
  final int maxDays;
  final int maxSizeMb;

  const HistoryConfig({
    this.maxCount = 100,
    this.maxDays = 365,
    this.maxSizeMb = 1024,
  });

  factory HistoryConfig.fromMap(Map<String, dynamic> map) {
    return HistoryConfig(
      maxCount: map['max_count'] as int? ?? 100,
      maxDays: map['max_days'] as int? ?? 365,
      maxSizeMb: map['max_size_mb'] as int? ?? 1024,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'max_count': maxCount,
      'max_days': maxDays,
      'max_size_mb': maxSizeMb,
    };
  }

  HistoryConfig copyWith({int? maxCount, int? maxDays, int? maxSizeMb}) {
    return HistoryConfig(
      maxCount: maxCount ?? this.maxCount,
      maxDays: maxDays ?? this.maxDays,
      maxSizeMb: maxSizeMb ?? this.maxSizeMb,
    );
  }

  bool shouldCleanup({
    required int commitCount,
    required int oldestCommitAge,
    required int objectsSizeMb,
  }) {
    if (maxCount > 0 && commitCount > maxCount) return true;
    if (maxDays > 0 && oldestCommitAge > maxDays) return true;
    if (maxSizeMb > 0 && objectsSizeMb > maxSizeMb) return true;
    return false;
  }
}
