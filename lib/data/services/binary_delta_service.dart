import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'app_log_service.dart';

/// 二进制增量存储服务
///
/// 提供二进制文件的增量存储能力，类似于 Git 的 packfile
/// 主要用于减少大文件的历史存储开销
class BinaryDeltaService {
  final String storagePath;
  final int deltaThreshold; // 触发增量存储的最小文件大小（字节）
  final AppLogService _appLog = AppLogService.instance;

  /// 默认阈值：1MB，超过此大小的文件考虑增量存储
  static const int defaultDeltaThreshold = 1024 * 1024;

  BinaryDeltaService({
    required this.storagePath,
    this.deltaThreshold = defaultDeltaThreshold,
  });

  /// 确保存储目录存在
  Future<void> ensureStorageExists() async {
    await _appLog.debug(
      category: 'binary_delta',
      message: 'Ensure binary delta storage exists',
      source: 'BinaryDeltaService.ensureStorageExists',
      context: {'storagePath': storagePath},
    );
    await Directory(storagePath).create(recursive: true);
    await Directory(p.join(storagePath, 'deltas')).create(recursive: true);
    await Directory(p.join(storagePath, 'objects')).create(recursive: true);
  }

  /// 存储文件的完整副本
  Future<String> storeFullObject(String filePath) async {
    await _appLog.debug(
      category: 'binary_delta',
      message: 'Store full object',
      source: 'BinaryDeltaService.storeFullObject',
      context: {'filePath': filePath},
    );

    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('File not found: $filePath');
    }

    await ensureStorageExists();

    final hash = await _computeFileHash(filePath);
    final objectPath = _getObjectPath(hash);

    if (!await File(objectPath).exists()) {
      await File(filePath).copy(objectPath);
    }

    return hash;
  }

  /// 计算并存储增量差异
  ///
  /// [newFilePath] 新文件路径
  /// [baseHash] 基础文件哈希
  /// 返回增量数据的哈希
  Future<DeltaResult> storeDelta({
    required String newFilePath,
    required String baseHash,
  }) async {
    await _appLog.debug(
      category: 'binary_delta',
      message: 'Store delta',
      source: 'BinaryDeltaService.storeDelta',
      context: {'newFilePath': newFilePath, 'baseHash': baseHash},
    );

    final baseObjectPath = _getObjectPath(baseHash);

    if (!await File(baseObjectPath).exists()) {
      throw StateError('Base object not found: $baseHash');
    }

    final newFile = File(newFilePath);
    if (!await newFile.exists()) {
      throw StateError('New file not found: $newFilePath');
    }

    final newFileSize = await newFile.length();

    // 小文件直接存储完整副本
    if (newFileSize < deltaThreshold) {
      final hash = await storeFullObject(newFilePath);
      return DeltaResult(
        hash: hash,
        isDelta: false,
        baseHash: null,
        compressedSize: newFileSize,
        originalSize: newFileSize,
      );
    }

    // 计算增量差异
    final delta = await _computeDelta(
      newFilePath: newFilePath,
      baseFilePath: baseObjectPath,
    );

    // 如果增量没有显著节省空间，存储完整副本
    final compressionRatio = delta.compressedSize / newFileSize;
    if (compressionRatio > 0.9) {
      final hash = await storeFullObject(newFilePath);
      return DeltaResult(
        hash: hash,
        isDelta: false,
        baseHash: null,
        compressedSize: newFileSize,
        originalSize: newFileSize,
      );
    }

    // 存储增量数据
    final deltaHash = await _computeDataHash(delta.data);
    final deltaPath = _getDeltaPath(deltaHash);

    if (!await File(deltaPath).exists()) {
      await File(deltaPath).writeAsBytes(delta.data);
    }

    return DeltaResult(
      hash: deltaHash,
      isDelta: true,
      baseHash: baseHash,
      compressedSize: delta.compressedSize,
      originalSize: delta.originalSize,
    );
  }

  /// 从增量恢复文件
  Future<void> restoreFromDelta({
    required String deltaHash,
    required String baseHash,
    required String targetPath,
  }) async {
    await _appLog.debug(
      category: 'binary_delta',
      message: 'Restore from delta',
      source: 'BinaryDeltaService.restoreFromDelta',
      context: {
        'deltaHash': deltaHash,
        'baseHash': baseHash,
        'targetPath': targetPath,
      },
    );

    final deltaPath = _getDeltaPath(deltaHash);
    final basePath = _getObjectPath(baseHash);

    if (!await File(deltaPath).exists()) {
      throw StateError('Delta not found: $deltaHash');
    }
    if (!await File(basePath).exists()) {
      throw StateError('Base object not found: $baseHash');
    }

    final deltaData = await File(deltaPath).readAsBytes();
    final baseData = await File(basePath).readAsBytes();

    final restoredData = _applyDelta(deltaData, baseData);

    await File(targetPath).parent.create(recursive: true);
    await File(targetPath).writeAsBytes(restoredData);
  }

  /// 计算增量差异
  ///
  /// 使用滑动窗口匹配算法，类似于 rsync/xdelta
  Future<DeltaData> _computeDelta({
    required String newFilePath,
    required String baseFilePath,
  }) async {
    final newData = await File(newFilePath).readAsBytes();
    final baseData = await File(baseFilePath).readAsBytes();

    // 使用内容定义分块进行差异检测
    final baseChunks = await _computeChunks(baseData);
    final deltaInstructions = <DeltaInstruction>[];

    var newOffset = 0;
    var copiedOffset = 0;

    // 构建块索引
    final chunkIndex = <String, int>{};
    for (var i = 0; i < baseChunks.length; i++) {
      chunkIndex[baseChunks[i].hash] = baseChunks[i].offset;
    }

    // 滑动窗口匹配
    final windowSize = 4096;
    final newDataHashes = <String>[];

    // 计算新数据的滚动哈希
    for (
      var offset = 0;
      offset < newData.length - windowSize;
      offset += windowSize
    ) {
      final end = (offset + windowSize > newData.length)
          ? newData.length
          : offset + windowSize;
      final chunk = newData.sublist(offset, end);
      final hash = _computeChunkHash(chunk);
      newDataHashes.add(hash);
    }

    // 匹配和生成指令
    while (newOffset < newData.length) {
      if (newOffset + windowSize > newData.length) {
        // 剩余数据作为插入指令
        deltaInstructions.add(
          DeltaInstruction.insert(data: newData.sublist(newOffset)),
        );
        break;
      }

      final windowHash = newDataHashes[(newOffset ~/ windowSize)];

      if (chunkIndex.containsKey(windowHash)) {
        // 先输出之前的插入数据
        if (copiedOffset < newOffset) {
          deltaInstructions.add(
            DeltaInstruction.insert(
              data: newData.sublist(copiedOffset, newOffset),
            ),
          );
        }

        // 复制指令
        final baseOffset = chunkIndex[windowHash]!;
        deltaInstructions.add(
          DeltaInstruction.copy(baseOffset: baseOffset, length: windowSize),
        );

        newOffset += windowSize;
        copiedOffset = newOffset;
      } else {
        newOffset += 256; // 小步进以找到匹配
      }
    }

    // 构建增量数据
    final deltaBuffer = BytesBuilder();

    for (final inst in deltaInstructions) {
      if (inst.isCopy) {
        // 复制指令格式: 0x00 + offset(4字节) + length(4字节)
        deltaBuffer.addByte(0x00);
        deltaBuffer.add(_intToBytes(inst.baseOffset ?? 0));
        deltaBuffer.add(_intToBytes(inst.length ?? 0));
      } else {
        // 插入指令格式: 0x01 + length(4字节) + data
        deltaBuffer.addByte(0x01);
        deltaBuffer.add(_intToBytes(inst.data!.length));
        deltaBuffer.add(inst.data!);
      }
    }

    return DeltaData(
      data: deltaBuffer.takeBytes(),
      compressedSize: deltaBuffer.length,
      originalSize: newData.length,
    );
  }

  /// 应用增量数据
  Uint8List _applyDelta(Uint8List deltaData, Uint8List baseData) {
    final output = BytesBuilder();
    var offset = 0;

    while (offset < deltaData.length) {
      final type = deltaData[offset];
      offset++;

      if (type == 0x00) {
        // 复制指令
        final baseOffset = _bytesToInt(deltaData.sublist(offset, offset + 4));
        offset += 4;
        final length = _bytesToInt(deltaData.sublist(offset, offset + 4));
        offset += 4;
        output.add(baseData.sublist(baseOffset, baseOffset + length));
      } else if (type == 0x01) {
        // 插入指令
        final length = _bytesToInt(deltaData.sublist(offset, offset + 4));
        offset += 4;
        output.add(deltaData.sublist(offset, offset + length));
        offset += length;
      }
    }

    return output.takeBytes();
  }

  /// 计算数据的分块
  Future<List<_ChunkInfo>> _computeChunks(Uint8List data) async {
    final chunks = <_ChunkInfo>[];
    const windowSize = 4096;

    for (var offset = 0; offset < data.length; offset += windowSize) {
      final end = (offset + windowSize > data.length)
          ? data.length
          : offset + windowSize;
      final chunk = data.sublist(offset, end);
      final hash = _computeChunkHash(chunk);
      chunks.add(_ChunkInfo(offset: offset, size: end - offset, hash: hash));
    }

    return chunks;
  }

  /// 计算块哈希
  String _computeChunkHash(Uint8List data) {
    final hash = sha256.convert(data);
    return hash.toString().substring(0, 16);
  }

  /// 计算文件哈希
  Future<String> _computeFileHash(String filePath) async {
    final file = File(filePath);
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  /// 计算数据哈希
  Future<String> _computeDataHash(Uint8List data) async {
    final hash = sha256.convert(data);
    return hash.toString();
  }

  /// 整数转字节
  Uint8List _intToBytes(int value) {
    return Uint8List(4)
      ..[0] = (value >> 24) & 0xFF
      ..[1] = (value >> 16) & 0xFF
      ..[2] = (value >> 8) & 0xFF
      ..[3] = value & 0xFF;
  }

  /// 字节转整数
  int _bytesToInt(Uint8List bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  /// 获取对象路径
  String _getObjectPath(String hash) {
    return p.join(storagePath, 'objects', hash.substring(0, 2), hash);
  }

  /// 获取增量路径
  String _getDeltaPath(String hash) {
    return p.join(storagePath, 'deltas', hash.substring(0, 2), hash);
  }

  /// 垃圾回收
  ///
  /// 清理不再被引用的增量和对象
  Future<int> garbageCollect(Set<String> activeHashes) async {
    await _appLog.info(
      category: 'binary_delta',
      message: 'Binary delta garbage collect started',
      source: 'BinaryDeltaService.garbageCollect',
      context: {'activeHashes': activeHashes.length},
    );

    var cleaned = 0;

    // 清理对象
    final objectsDir = Directory(p.join(storagePath, 'objects'));
    if (await objectsDir.exists()) {
      await for (final entity in objectsDir.list(recursive: true)) {
        if (entity is File) {
          final hash = p.basename(entity.path);
          if (!activeHashes.contains(hash)) {
            await entity.delete();
            cleaned++;
          }
        }
      }
    }

    // 清理增量
    final deltasDir = Directory(p.join(storagePath, 'deltas'));
    if (await deltasDir.exists()) {
      await for (final entity in deltasDir.list(recursive: true)) {
        if (entity is File) {
          final hash = p.basename(entity.path);
          if (!activeHashes.contains(hash)) {
            await entity.delete();
            cleaned++;
          }
        }
      }
    }

    await _appLog.info(
      category: 'binary_delta',
      message: 'Binary delta garbage collect completed',
      source: 'BinaryDeltaService.garbageCollect',
      context: {'cleaned': cleaned},
    );
    return cleaned;
  }

  /// 获取存储统计
  Future<StorageStats> getStats() async {
    await _appLog.debug(
      category: 'binary_delta',
      message: 'Read binary delta storage stats',
      source: 'BinaryDeltaService.getStats',
      context: {'storagePath': storagePath},
    );

    var objectCount = 0;
    var objectSize = 0;
    var deltaCount = 0;
    var deltaSize = 0;

    final objectsDir = Directory(p.join(storagePath, 'objects'));
    if (await objectsDir.exists()) {
      await for (final entity in objectsDir.list(recursive: true)) {
        if (entity is File) {
          objectCount++;
          objectSize += await entity.length();
        }
      }
    }

    final deltasDir = Directory(p.join(storagePath, 'deltas'));
    if (await deltasDir.exists()) {
      await for (final entity in deltasDir.list(recursive: true)) {
        if (entity is File) {
          deltaCount++;
          deltaSize += await entity.length();
        }
      }
    }

    return StorageStats(
      objectCount: objectCount,
      objectSize: objectSize,
      deltaCount: deltaCount,
      deltaSize: deltaSize,
    );
  }
}

/// 增量结果
class DeltaResult {
  final String hash;
  final bool isDelta;
  final String? baseHash;
  final int compressedSize;
  final int originalSize;

  DeltaResult({
    required this.hash,
    required this.isDelta,
    this.baseHash,
    required this.compressedSize,
    required this.originalSize,
  });

  double get compressionRatio => compressedSize / originalSize;
}

/// 增量数据
class DeltaData {
  final Uint8List data;
  final int compressedSize;
  final int originalSize;

  DeltaData({
    required this.data,
    required this.compressedSize,
    required this.originalSize,
  });
}

/// 增量指令
class DeltaInstruction {
  final bool isCopy;
  final int? baseOffset;
  final int? length;
  final Uint8List? data;

  DeltaInstruction._({
    required this.isCopy,
    this.baseOffset,
    this.length,
    this.data,
  });

  factory DeltaInstruction.copy({
    required int baseOffset,
    required int length,
  }) =>
      DeltaInstruction._(isCopy: true, baseOffset: baseOffset, length: length);

  factory DeltaInstruction.insert({required Uint8List data}) =>
      DeltaInstruction._(isCopy: false, data: data);
}

/// 存储统计
class StorageStats {
  final int objectCount;
  final int objectSize;
  final int deltaCount;
  final int deltaSize;

  StorageStats({
    required this.objectCount,
    required this.objectSize,
    required this.deltaCount,
    required this.deltaSize,
  });

  int get totalSize => objectSize + deltaSize;
  int get totalCount => objectCount + deltaCount;
  double get deltaRatio => deltaCount / (totalCount == 0 ? 1 : totalCount);
}

/// 块信息（内部使用）
class _ChunkInfo {
  final int offset;
  final int size;
  final String hash;

  _ChunkInfo({required this.offset, required this.size, required this.hash});
}
