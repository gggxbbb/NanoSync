import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 文件校验工具
///
/// 提供多种哈希算法，针对二进制文件优化
class ChecksumUtil {
  ChecksumUtil._();

  /// CRC32查找表（优化版本 - 使用 Uint32List 提高性能）
  static final Uint32List _crc32Table = _generateCrc32Table();

  static Uint32List _generateCrc32Table() {
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

  /// 计算字节数据的CRC32
  static int _crc32FromBytes(Uint8List bytes) {
    int crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// 计算文件CRC32校验码
  static Future<String> calculateCrc32(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      final bytes = await file.readAsBytes();
      final crc = _crc32FromBytes(bytes);
      return crc.toRadixString(16).padLeft(8, '0');
    } catch (e) {
      return '';
    }
  }

  /// 计算文件SHA256校验码
  static Future<String> calculateSha256(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      final stream = file.openRead();
      final hash = await sha256.bind(stream).first;
      return hash.toString();
    } catch (e) {
      return '';
    }
  }

  /// 计算字节数据CRC32
  static String calculateCrc32FromBytes(Uint8List bytes) {
    final crc = _crc32FromBytes(bytes);
    return crc.toRadixString(16).padLeft(8, '0');
  }

  /// 计算大文件CRC32（分片读取，优化版本）
  ///
  /// 使用 readInto 而不是 read 以减少内存分配
  static Future<String> calculateCrc32Chunked(
    String filePath, {
    int chunkSize = 4 * 1024 * 1024,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';

      final fileSize = await file.length();

      // 小文件直接读取
      if (fileSize <= chunkSize) {
        return calculateCrc32(filePath);
      }

      int crc = 0xFFFFFFFF;
      final raf = await file.open(mode: FileMode.read);

      try {
        // 预分配缓冲区，避免多次分配
        final buffer = Uint8List(chunkSize);

        while (true) {
          final bytesRead = await raf.readInto(buffer);
          if (bytesRead == 0) break;

          // 只处理实际读取的字节
          for (int i = 0; i < bytesRead; i++) {
            crc = _crc32Table[(crc ^ buffer[i]) & 0xFF] ^ (crc >> 8);
          }
        }
      } finally {
        await raf.close();
      }

      final result = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
      return result.toRadixString(16).padLeft(8, '0');
    } catch (e) {
      return '';
    }
  }

  /// 批量计算文件CRC32（并行优化）
  ///
  /// 适用于需要同时计算多个文件哈希的场景
  static Future<Map<String, String>> batchCalculateCrc32(
    List<String> filePaths, {
    int parallelism = 4,
    int chunkSize = 4 * 1024 * 1024,
  }) async {
    final results = <String, String>{};

    // 分批并行处理
    for (var i = 0; i < filePaths.length; i += parallelism) {
      final batch = filePaths.skip(i).take(parallelism);
      final futures = batch.map((path) async {
        final hash = await calculateCrc32Chunked(path, chunkSize: chunkSize);
        return MapEntry(path, hash);
      });

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        results[entry.key] = entry.value;
      }
    }

    return results;
  }

  /// 快速检查文件是否已更改（基于大小和修改时间）
  ///
  /// 返回 true 表示文件可能已更改，需要进一步验证
  /// 返回 false 表示文件确定未更改
  static Future<bool> quickFileCheck({
    required String filePath,
    required int knownSize,
    required DateTime knownModifiedTime,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return true;

      final stat = await file.stat();

      // 文件大小不同，确定已更改
      if (stat.size != knownSize) return true;

      // 修改时间差异在 1 秒内，认为未更改
      final timeDiff = stat.modified.difference(knownModifiedTime).abs();
      if (timeDiff.inSeconds < 1) return false;

      // 需要进一步验证
      return true;
    } catch (_) {
      return true;
    }
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
