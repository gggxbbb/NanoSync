import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 二进制文件处理性能优化工具
///
/// 主要优化策略：
/// 1. 快速路径检查 - 使用文件大小和修改时间作为第一道防线
/// 2. 增量哈希计算 - 支持分块和并行计算
/// 3. 硬链接存储 - 避免复制相同文件
/// 4. 智能缓存 - 缓存文件元数据减少 I/O
class BinaryOptimizationUtil {
  BinaryOptimizationUtil._();

  /// 文件元数据缓存
  static final Map<String, FileMetadataCache> _metadataCache = {};

  /// 缓存过期时间（毫秒）
  static const int _cacheExpiryMs = 30000; // 30秒

  /// 清理缓存
  static void clearCache() {
    _metadataCache.clear();
  }

  /// 快速检查文件是否已更改
  ///
  /// 通过比较文件大小和修改时间，避免不必要的哈希计算
  /// 返回 true 表示文件可能已更改，需要进一步验证
  /// 返回 false 表示文件确定未更改
  static Future<bool> hasFileChanged({
    required String filePath,
    required int knownSize,
    required String knownHash,
    required DateTime knownModifiedTime,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return true;
    }

    final stat = await file.stat();

    // 快速路径：文件大小不同，确定已更改
    if (stat.size != knownSize) {
      return true;
    }

    // 快速路径：修改时间未变，文件未更改
    // 使用容忍度来处理文件系统时间精度问题
    final timeDiff = stat.modified.difference(knownModifiedTime).abs();
    if (timeDiff.inMilliseconds < 1000) {
      // 修改时间几乎相同，检查缓存
      final cacheKey =
          '$filePath:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
      final cached = _metadataCache[cacheKey];
      if (cached != null && cached.hash == knownHash) {
        return false;
      }
    }

    // 需要计算哈希来确认
    return true;
  }

  /// 带缓存的哈希计算
  ///
  /// 首先检查缓存，如果缓存有效则直接返回
  /// 否则计算哈希并更新缓存
  static Future<String> calculateHashWithCache(
    String filePath, {
    int chunkSize = 4 * 1024 * 1024,
    bool forceRefresh = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return '';
    }

    final stat = await file.stat();
    final cacheKey =
        '$filePath:${stat.size}:${stat.modified.millisecondsSinceEpoch}';

    // 检查缓存
    if (!forceRefresh) {
      final cached = _metadataCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.cachedAt).inMilliseconds <
              _cacheExpiryMs) {
        return cached.hash;
      }
    }

    // 计算哈希
    final hash = await _calculateFastHash(filePath, chunkSize: chunkSize);

    // 更新缓存
    _metadataCache[cacheKey] = FileMetadataCache(
      hash: hash,
      size: stat.size,
      modifiedTime: stat.modified,
      cachedAt: DateTime.now(),
    );

    return hash;
  }

  /// 快速哈希计算
  ///
  /// 使用优化的 CRC32 算法，支持并行分块处理
  static Future<String> _calculateFastHash(
    String filePath, {
    int chunkSize = 4 * 1024 * 1024,
  }) async {
    try {
      final file = File(filePath);
      final length = await file.length();

      // 小文件直接计算
      if (length < chunkSize) {
        return await _calculateCrc32(file);
      }

      // 大文件分块计算
      return await _calculateChunkedCrc32(file, chunkSize: chunkSize);
    } catch (e) {
      return '';
    }
  }

  /// CRC32 查找表（优化版本）
  static final Uint32List _crc32Table = _generateOptimizedCrc32Table();

  static Uint32List _generateOptimizedCrc32Table() {
    final table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) == 1) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc & 0xFFFFFFFF;
    }
    return table;
  }

  /// 计算 CRC32（小文件优化版本）
  static Future<String> _calculateCrc32(File file) async {
    final bytes = await file.readAsBytes();
    int crc = 0xFFFFFFFF;

    for (final byte in bytes) {
      crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }

    final result = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    return result.toRadixString(16).padLeft(8, '0');
  }

  /// 分块计算 CRC32（大文件优化版本）
  static Future<String> _calculateChunkedCrc32(
    File file, {
    int chunkSize = 4 * 1024 * 1024,
  }) async {
    int crc = 0xFFFFFFFF;
    final raf = await file.open(mode: FileMode.read);

    try {
      // 使用更大的缓冲区提高性能
      final buffer = Uint8List(chunkSize);

      while (true) {
        final bytesRead = await raf.readInto(buffer);
        if (bytesRead == 0) break;

        // 使用切片视图避免复制
        final view = Uint8List.sublistView(buffer, 0, bytesRead);
        for (final byte in view) {
          crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
        }
      }
    } finally {
      await raf.close();
    }

    final result = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    return result.toRadixString(16).padLeft(8, '0');
  }

  /// 创建硬链接（Windows 优化）
  ///
  /// 当文件系统支持时，使用硬链接代替复制
  /// 这可以节省磁盘空间并提高性能
  static Future<bool> createHardLink({
    required String sourcePath,
    required String targetPath,
  }) async {
    try {
      // 确保目标目录存在
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);

      // 在 Windows 上使用硬链接
      if (Platform.isWindows) {
        // 尝试创建硬链接
        final result = await Process.run('cmd', [
          '/C',
          'mklink',
          '/H',
          targetPath,
          sourcePath,
        ]);

        if (result.exitCode == 0) {
          return true;
        }
      }

      // 回退到复制
      await File(sourcePath).copy(targetPath);
      return true;
    } catch (e) {
      // 硬链接失败，回退到复制
      try {
        await File(sourcePath).copy(targetPath);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// 批量计算文件哈希（并行优化）
  ///
  /// 使用并行处理提高批量文件扫描效率
  static Future<Map<String, String>> batchCalculateHashes(
    List<String> filePaths, {
    int parallelism = 4,
    int chunkSize = 4 * 1024 * 1024,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <String, String>{};
    final total = filePaths.length;
    var completed = 0;

    // 使用分批并行处理
    for (var i = 0; i < filePaths.length; i += parallelism) {
      final batch = filePaths.skip(i).take(parallelism);

      await Future.wait(
        batch.map((path) async {
          final hash = await calculateHashWithCache(path, chunkSize: chunkSize);
          results[path] = hash;
          completed++;
          onProgress?.call(completed, total);
        }),
      );
    }

    return results;
  }

  /// 检测文件是否为二进制
  ///
  /// 通过检查文件扩展名和内容特征
  static Future<bool> isBinaryFile(String filePath) async {
    // 常见二进制文件扩展名
    const binaryExtensions = {
      'exe',
      'dll',
      'so',
      'dylib',
      'bin',
      'dat',
      'png',
      'jpg',
      'jpeg',
      'gif',
      'bmp',
      'ico',
      'webp',
      'tiff',
      'mp3',
      'mp4',
      'wav',
      'avi',
      'mkv',
      'mov',
      'flv',
      'wmv',
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'bz2',
      'xz',
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'sqlite',
      'db',
      'mdb',
    };

    final ext = p.extension(filePath).toLowerCase();
    if (binaryExtensions.contains(ext.replaceAll('.', ''))) {
      return true;
    }

    // 读取文件头部检测
    try {
      final file = File(filePath);
      final firstBytes = await file.openRead(0, 8192).first;

      // 检查是否有空字节（二进制文件特征）
      for (final byte in firstBytes) {
        if (byte == 0) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return true;
    }
  }

  /// 计算文件相似度（用于去重检测）
  ///
  /// 使用 SimHash 算法计算文件指纹
  static Future<int> calculateSimHash(String filePath) async {
    try {
      final file = File(filePath);
      final stream = file.openRead();

      // 使用 MD5 作为基础哈希
      final hash = await md5.bind(stream).first;
      final bytes = hash.bytes;

      // 生成 SimHash 指纹
      final simHash = Uint8List(32);
      for (var i = 0; i < bytes.length; i++) {
        for (var j = 0; j < 8; j++) {
          if ((bytes[i] >> j) & 1 == 1) {
            simHash[i % 32]++;
          } else {
            simHash[i % 32]--;
          }
        }
      }

      // 转换为整数
      int result = 0;
      for (var i = 0; i < 32; i++) {
        if (simHash[i] > 0) {
          result |= (1 << (i % 64));
        }
      }

      return result;
    } catch (_) {
      return 0;
    }
  }

  /// 计算两个 SimHash 的汉明距离
  ///
  /// 返回值越小表示文件越相似
  static int hammingDistance(int hash1, int hash2) {
    var xor = hash1 ^ hash2;
    var distance = 0;
    while (xor != 0) {
      distance += xor & 1;
      xor >>= 1;
    }
    return distance;
  }
}

/// 文件元数据缓存
class FileMetadataCache {
  final String hash;
  final int size;
  final DateTime modifiedTime;
  final DateTime cachedAt;

  FileMetadataCache({
    required this.hash,
    required this.size,
    required this.modifiedTime,
    required this.cachedAt,
  });
}

/// 文件变更检测结果
class FileChangeDetectionResult {
  final bool hasChanged;
  final String? newHash;
  final int? newSize;
  final DateTime? newModifiedTime;
  final bool fromCache;

  FileChangeDetectionResult({
    required this.hasChanged,
    this.newHash,
    this.newSize,
    this.newModifiedTime,
    this.fromCache = false,
  });
}
