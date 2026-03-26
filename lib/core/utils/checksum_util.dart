import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 文件校验工具
class ChecksumUtil {
  ChecksumUtil._();

  /// CRC32查找表
  static final List<int> _crc32Table = _generateCrc32Table();

  static List<int> _generateCrc32Table() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) == 1) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc;
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

  /// 计算大文件CRC32（分片读取）
  static Future<String> calculateCrc32Chunked(String filePath,
      {int chunkSize = 4 * 1024 * 1024}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      int crc = 0xFFFFFFFF;
      final raf = await file.open(mode: FileMode.read);
      try {
        while (true) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;
          for (final byte in chunk) {
            crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
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
