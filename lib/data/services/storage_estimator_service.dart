import 'dart:io';

import 'app_log_service.dart';

class StorageEstimate {
  final int currentBytes;
  final int estimatedExtraBytes;
  final double changeRate;

  const StorageEstimate({
    required this.currentBytes,
    required this.estimatedExtraBytes,
    required this.changeRate,
  });
}

class StorageEstimatorService {
  static StorageEstimatorService? _instance;
  final AppLogService _appLog;

  StorageEstimatorService._({AppLogService? appLog})
    : _appLog = appLog ?? AppLogService.instance;

  static StorageEstimatorService get instance {
    _instance ??= StorageEstimatorService._();
    return _instance!;
  }

  Future<StorageEstimate> estimateRetentionOverhead({
    required String rootPath,
    required int maxVersions,
    required int maxDays,
    required int maxSizeGB,
  }) async {
    await _appLog.debug(
      category: 'storage',
      message: 'Estimate retention overhead started',
      source: 'StorageEstimatorService.estimateRetentionOverhead',
      context: {
        'rootPath': rootPath,
        'maxVersions': maxVersions,
        'maxDays': maxDays,
        'maxSizeGB': maxSizeGB,
      },
    );

    final scan = await _scanDirectory(rootPath);

    final textRatio = scan.fileCount == 0
        ? 0.7
        : (scan.textFileCount / scan.fileCount);
    final smallFileRatio = scan.fileCount == 0
        ? 0.6
        : (scan.smallFileCount / scan.fileCount);
    final avgFileSize = scan.fileCount == 0
        ? 0
        : (scan.totalBytes / scan.fileCount);

    var changeRate = 0.06 + textRatio * 0.12 + smallFileRatio * 0.08;
    if (scan.fileCount > 10000) {
      changeRate += 0.06;
    }
    if (avgFileSize < 256 * 1024) {
      changeRate += 0.04;
    }
    changeRate = changeRate.clamp(0.05, 0.35);

    final versionsFactor = (maxVersions / 20).clamp(0.2, 6.0);
    final daysFactor = (maxDays / 90).clamp(0.2, 8.0);
    final retentionFactor = (0.6 + versionsFactor * 0.45 + daysFactor * 0.25)
        .clamp(0.4, 4.5);

    final estimated = (scan.totalBytes * changeRate * retentionFactor).round();
    final capBytes = maxSizeGB * 1024 * 1024 * 1024;
    final capped = estimated.clamp(0, capBytes);

    final result = StorageEstimate(
      currentBytes: scan.totalBytes,
      estimatedExtraBytes: capped,
      changeRate: changeRate,
    );

    await _appLog.debug(
      category: 'storage',
      message: 'Estimate retention overhead completed',
      source: 'StorageEstimatorService.estimateRetentionOverhead',
      context: {
        'currentBytes': result.currentBytes,
        'estimatedExtraBytes': result.estimatedExtraBytes,
        'changeRate': result.changeRate,
      },
    );

    return result;
  }

  Future<_ScanStats> _scanDirectory(String rootPath) async {
    var totalBytes = 0;
    var fileCount = 0;
    var textFileCount = 0;
    var smallFileCount = 0;
    final root = Directory(rootPath);
    if (!await root.exists()) {
      return const _ScanStats();
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('/.nanosync/') || normalized.contains('/.git/')) {
        continue;
      }

      try {
        final len = await entity.length();
        totalBytes += len;
        fileCount++;
        if (len <= 256 * 1024) {
          smallFileCount++;
        }
        if (_isLikelyTextFile(entity.path)) {
          textFileCount++;
        }
      } catch (_) {}
    }

    return _ScanStats(
      totalBytes: totalBytes,
      fileCount: fileCount,
      textFileCount: textFileCount,
      smallFileCount: smallFileCount,
    );
  }

  bool _isLikelyTextFile(String path) {
    final lower = path.toLowerCase();
    const textExt = [
      '.txt',
      '.md',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.csv',
      '.log',
      '.dart',
      '.js',
      '.ts',
      '.tsx',
      '.jsx',
      '.java',
      '.kt',
      '.py',
      '.go',
      '.rs',
      '.c',
      '.cpp',
      '.h',
      '.hpp',
      '.cs',
      '.html',
      '.css',
      '.scss',
      '.sh',
      '.bat',
      '.ps1',
      '.ini',
      '.toml',
    ];
    return textExt.any(lower.endsWith);
  }
}

class _ScanStats {
  final int totalBytes;
  final int fileCount;
  final int textFileCount;
  final int smallFileCount;

  const _ScanStats({
    this.totalBytes = 0,
    this.fileCount = 0,
    this.textFileCount = 0,
    this.smallFileCount = 0,
  });
}
