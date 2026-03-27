class FetchResult {
  final int ahead;
  final int behind;
  final String remoteHead;
  final bool hasUpdates;
  final String? error;

  const FetchResult({
    this.ahead = 0,
    this.behind = 0,
    this.remoteHead = '',
    this.hasUpdates = false,
    this.error,
  });

  bool get isSuccess => error == null;
  bool get needsPull => behind > 0;
  bool get needsPush => ahead > 0;
}

class PushResult {
  final int pushedCommits;
  final int pushedObjects;
  final bool success;
  final String? error;

  const PushResult({
    this.pushedCommits = 0,
    this.pushedObjects = 0,
    this.success = false,
    this.error,
  });
}

class PullResult {
  final int pulledCommits;
  final List<String> mergedFiles;
  final List<String> conflicts;
  final bool success;
  final String? error;

  const PullResult({
    this.pulledCommits = 0,
    this.mergedFiles = const [],
    this.conflicts = const [],
    this.success = false,
    this.error,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

class SyncResult {
  final int pushedCommits;
  final int pulledCommits;
  final int pushedObjects;
  final int pulledObjects;
  final List<String> conflicts;
  final bool success;
  final String? error;

  const SyncResult({
    this.pushedCommits = 0,
    this.pulledCommits = 0,
    this.pushedObjects = 0,
    this.pulledObjects = 0,
    this.conflicts = const [],
    this.success = false,
    this.error,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

class CloneResult {
  final String repositoryId;
  final int downloadedObjects;
  final int totalFiles;
  final bool success;
  final String? error;

  const CloneResult({
    this.repositoryId = '',
    this.downloadedObjects = 0,
    this.totalFiles = 0,
    this.success = false,
    this.error,
  });
}

class CleanupResult {
  final int deletedCommits;
  final int deletedObjects;
  final int freedSizeMb;
  final bool success;
  final String? error;

  const CleanupResult({
    this.deletedCommits = 0,
    this.deletedObjects = 0,
    this.freedSizeMb = 0,
    this.success = false,
    this.error,
  });
}

class HistoryStats {
  final int commitCount;
  final int oldestCommitAge;
  final int objectsSizeMb;
  final int objectsCount;

  const HistoryStats({
    this.commitCount = 0,
    this.oldestCommitAge = 0,
    this.objectsSizeMb = 0,
    this.objectsCount = 0,
  });
}
