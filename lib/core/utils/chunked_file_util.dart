import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

/// 分块存储管理器
///
/// 用于大文件的增量存储和传输优化
/// 采用类似 Git LFS 和 rsync 的分块策略
class ChunkedFileStorage {
  final String storagePath;
  final int chunkSize;

  /// 默认块大小：4MB
  static const int defaultChunkSize = 4 * 1024 * 1024;

  /// 最小块大小：64KB
  static const int minChunkSize = 64 * 1024;

  /// 最大块大小：64MB
  static const int maxChunkSize = 64 * 1024 * 1024;

  ChunkedFileStorage({
    required this.storagePath,
    this.chunkSize = defaultChunkSize,
  });

  /// 确保存储目录存在
  Future<void> ensureStorageExists() async {
    await Directory(storagePath).create(recursive: true);
  }

  /// 计算文件的分块信息
  ///
  /// 使用滚动哈希确定块边界，实现内容定义分块
  Future<List<FileChunk>> computeChunks(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return [];
    }

    final fileSize = await file.length();
    final chunks = <FileChunk>[];

    // 小文件直接作为一个块
    if (fileSize <= chunkSize) {
      final hash = await _computeChunkHash(file, 0, fileSize);
      chunks.add(FileChunk(index: 0, offset: 0, size: fileSize, hash: hash));
      return chunks;
    }

    // 大文件分块处理
    final raf = await file.open(mode: FileMode.read);
    try {
      var offset = 0;
      var index = 0;

      while (offset < fileSize) {
        final remainingBytes = fileSize - offset;
        final currentChunkSize = remainingBytes > chunkSize
            ? chunkSize
            : remainingBytes;

        final hash = await _computeChunkHashFromOpenFile(
          raf,
          offset,
          currentChunkSize,
        );
        chunks.add(
          FileChunk(
            index: index,
            offset: offset,
            size: currentChunkSize,
            hash: hash,
          ),
        );

        offset += currentChunkSize;
        index++;
      }
    } finally {
      await raf.close();
    }

    return chunks;
  }

  /// 使用滚动哈希计算内容定义分块（CDC）
  ///
  /// 更适合相似文件的差异检测
  Future<List<FileChunk>> computeContentDefinedChunks(
    String filePath, {
    int minChunk = 2 * 1024 * 1024, // 2MB 最小
    int maxChunk = 8 * 1024 * 1024, // 8MB 最大
    int targetChunk = 4 * 1024 * 1024, // 4MB 目标
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return [];
    }

    final fileSize = await file.length();
    if (fileSize <= minChunk) {
      final hash = await _computeChunkHash(file, 0, fileSize);
      return [FileChunk(index: 0, offset: 0, size: fileSize, hash: hash)];
    }

    final chunks = <FileChunk>[];
    final raf = await file.open(mode: FileMode.read);

    try {
      var offset = 0;
      var index = 0;
      final buffer = Uint8List(64 * 1024); // 64KB 缓冲区
      var bufferPos = 0;
      var chunkStart = 0;
      var bytesInChunk = 0;

      // 滚动哈希参数
      const prime = 31;
      const mask = 0xFFFFFFFF;
      const targetBits = 23; // 平均块大小约 4MB
      const targetMask = (1 << targetBits) - 1;

      var rollingHash = 0;

      while (true) {
        final bytesRead = await raf.readInto(buffer);
        if (bytesRead == 0) break;

        for (var i = 0; i < bytesRead; i++) {
          final byte = buffer[i];
          rollingHash = ((rollingHash * prime) + byte) & mask;
          bufferPos++;
          bytesInChunk++;

          // 检查是否达到分块条件
          final shouldSplit =
              (bytesInChunk >= minChunk && (rollingHash & targetMask) == 0) ||
              bytesInChunk >= maxChunk;

          if (shouldSplit) {
            final chunkEnd = offset + bufferPos;
            final hash = await _computeChunkHashFromOpenFile(
              raf,
              chunkStart,
              bytesInChunk,
            );
            chunks.add(
              FileChunk(
                index: index,
                offset: chunkStart,
                size: bytesInChunk,
                hash: hash,
              ),
            );

            index++;
            chunkStart = chunkEnd;
            bytesInChunk = 0;
            rollingHash = 0;
          }
        }

        offset += bytesRead;
      }

      // 处理最后一块
      if (bytesInChunk > 0) {
        final hash = await _computeChunkHashFromOpenFile(
          raf,
          chunkStart,
          bytesInChunk,
        );
        chunks.add(
          FileChunk(
            index: index,
            offset: chunkStart,
            size: bytesInChunk,
            hash: hash,
          ),
        );
      }
    } finally {
      await raf.close();
    }

    return chunks;
  }

  /// 计算块哈希
  Future<String> _computeChunkHash(File file, int offset, int size) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      return await _computeChunkHashFromOpenFile(raf, offset, size);
    } finally {
      await raf.close();
    }
  }

  /// 从已打开的文件计算块哈希
  Future<String> _computeChunkHashFromOpenFile(
    RandomAccessFile raf,
    int offset,
    int size,
  ) async {
    await raf.setPosition(offset);
    final bytes = await raf.read(size);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// 存储文件块
  Future<void> storeChunk(String chunkHash, Uint8List data) async {
    await ensureStorageExists();
    final chunkPath = _getChunkPath(chunkHash);

    if (!await File(chunkPath).exists()) {
      await File(chunkPath).writeAsBytes(data);
    }
  }

  /// 读取文件块
  Future<Uint8List?> readChunk(String chunkHash) async {
    final chunkPath = _getChunkPath(chunkHash);
    final file = File(chunkPath);

    if (!await file.exists()) {
      return null;
    }

    return await file.readAsBytes();
  }

  /// 检查块是否存在
  Future<bool> chunkExists(String chunkHash) async {
    final chunkPath = _getChunkPath(chunkHash);
    return await File(chunkPath).exists();
  }

  /// 获取块存储路径
  String _getChunkPath(String hash) {
    // 使用前两个字符作为子目录，避免单个目录文件过多
    return p.join(storagePath, hash.substring(0, 2), hash);
  }

  /// 将文件存储为分块
  ///
  /// 返回文件清单
  Future<FileManifest> storeFileAsChunks(String filePath) async {
    final file = File(filePath);
    final fileName = p.basename(filePath);
    final fileSize = await file.length();

    final chunks = await computeChunks(filePath);

    // 存储每个块
    final raf = await file.open(mode: FileMode.read);
    try {
      for (final chunk in chunks) {
        final chunkPath = _getChunkPath(chunk.hash);

        if (!await File(chunkPath).exists()) {
          await File(chunkPath).parent.create(recursive: true);
          await raf.setPosition(chunk.offset);
          final data = await raf.read(chunk.size.toInt());
          await File(chunkPath).writeAsBytes(data);
        }
      }
    } finally {
      await raf.close();
    }

    return FileManifest(fileName: fileName, fileSize: fileSize, chunks: chunks);
  }

  /// 从分块重建文件
  Future<void> rebuildFile(FileManifest manifest, String targetPath) async {
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    final raf = await targetFile.open(mode: FileMode.write);
    try {
      for (final chunk in manifest.chunks) {
        final chunkPath = _getChunkPath(chunk.hash);

        if (!await File(chunkPath).exists()) {
          throw StateError('Chunk not found: ${chunk.hash}');
        }

        final data = await File(chunkPath).readAsBytes();
        await raf.setPosition(chunk.offset);
        await raf.writeFrom(data);
      }
    } finally {
      await raf.close();
    }
  }

  /// 计算两个文件清单的差异
  ///
  /// 返回需要传输的块列表
  ChunkDiff computeDiff(FileManifest source, FileManifest target) {
    final sourceChunks = {for (var c in source.chunks) c.hash: c};
    final targetChunks = {for (var c in target.chunks) c.hash: c};

    final added = <FileChunk>[];
    final removed = <FileChunk>[];
    final unchanged = <FileChunk>[];

    // 找出新增的块
    for (final chunk in target.chunks) {
      if (!sourceChunks.containsKey(chunk.hash)) {
        added.add(chunk);
      } else {
        unchanged.add(chunk);
      }
    }

    // 找出删除的块
    for (final chunk in source.chunks) {
      if (!targetChunks.containsKey(chunk.hash)) {
        removed.add(chunk);
      }
    }

    return ChunkDiff(added: added, removed: removed, unchanged: unchanged);
  }

  /// 清理未使用的块
  Future<int> garbageCleanup(Set<String> usedChunkHashes) async {
    var cleaned = 0;

    await for (final entity in Directory(storagePath).list(recursive: true)) {
      if (entity is File) {
        final hash = p.basename(entity.path);
        if (!usedChunkHashes.contains(hash)) {
          await entity.delete();
          cleaned++;
        }
      }
    }

    return cleaned;
  }
}

/// 文件块信息
class FileChunk {
  final int index;
  final int offset;
  final int size;
  final String hash;

  FileChunk({
    required this.index,
    required this.offset,
    required this.size,
    required this.hash,
  });

  Map<String, dynamic> toMap() => {
    'index': index,
    'offset': offset,
    'size': size,
    'hash': hash,
  };

  factory FileChunk.fromMap(Map<String, dynamic> map) => FileChunk(
    index: map['index'] as int,
    offset: map['offset'] as int,
    size: map['size'] as int,
    hash: map['hash'] as String,
  );
}

/// 文件清单
class FileManifest {
  final String fileName;
  final int fileSize;
  final List<FileChunk> chunks;

  FileManifest({
    required this.fileName,
    required this.fileSize,
    required this.chunks,
  });

  /// 计算整个文件的哈希
  String get fileHash {
    if (chunks.isEmpty) return '';
    if (chunks.length == 1) return chunks.first.hash;

    // 组合所有块哈希计算文件哈希
    final combined = chunks.map((c) => c.hash).join('');
    return sha256.convert(combined.codeUnits).toString();
  }

  Map<String, dynamic> toMap() => {
    'fileName': fileName,
    'fileSize': fileSize,
    'chunks': chunks.map((c) => c.toMap()).toList(),
  };

  factory FileManifest.fromMap(Map<String, dynamic> map) => FileManifest(
    fileName: map['fileName'] as String,
    fileSize: map['fileSize'] as int,
    chunks: (map['chunks'] as List)
        .map((c) => FileChunk.fromMap(c as Map<String, dynamic>))
        .toList(),
  );
}

/// 块差异
class ChunkDiff {
  final List<FileChunk> added;
  final List<FileChunk> removed;
  final List<FileChunk> unchanged;

  ChunkDiff({
    required this.added,
    required this.removed,
    required this.unchanged,
  });

  /// 计算传输节省比例
  double get savingRatio {
    final total = added.length + unchanged.length;
    if (total == 0) return 0;
    return unchanged.length / total;
  }
}
