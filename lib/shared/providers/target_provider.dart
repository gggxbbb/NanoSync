import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/constants/enums.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/sync_target.dart';
import '../../data/models/sync_task.dart';
import '../../data/services/smb_service.dart';
import '../../data/services/webdav_service.dart';

enum TargetOnlineState { unknown, checking, online, offline }

class TargetStatusInfo {
  const TargetStatusInfo({
    this.state = TargetOnlineState.unknown,
    this.message,
    this.lastCheckedAt,
  });

  final TargetOnlineState state;
  final String? message;
  final DateTime? lastCheckedAt;

  TargetStatusInfo copyWith({
    TargetOnlineState? state,
    String? message,
    DateTime? lastCheckedAt,
  }) {
    return TargetStatusInfo(
      state: state ?? this.state,
      message: message ?? this.message,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// 远端目标配置 Provider（独立于同步任务）
class TargetProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final WebDAVService _webdavService = WebDAVService();
  final SmbService _smbService = SmbService();

  List<SyncTarget> _targets = [];
  final Map<String, TargetStatusInfo> _statusMap = {};
  final Map<String, int> _usageMap = {};
  Timer? _statusRefreshTimer;
  Duration _statusRefreshInterval = const Duration(seconds: 30);
  bool _isRefreshingStatuses = false;
  bool _isLoading = false;
  String? _error;
  String _defaultWebDavProbePath = '/';

  List<SyncTarget> get targets => _targets;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAutoRefreshing => _statusRefreshTimer?.isActive ?? false;
  Duration get statusRefreshInterval => _statusRefreshInterval;
  String get defaultWebDavProbePath => _defaultWebDavProbePath;

  TargetStatusInfo statusOf(String targetId) =>
      _statusMap[targetId] ?? const TargetStatusInfo();

  int usageCountOf(String targetId) => _usageMap[targetId] ?? 0;

  void setDefaultWebDavProbePath(String value) {
    final normalized = _normalizeProbePath(value);
    if (normalized == _defaultWebDavProbePath) {
      return;
    }
    _defaultWebDavProbePath = normalized;
    notifyListeners();
  }

  Future<void> loadTargets({bool refreshStatuses = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final maps = await _db.getAllTargets();
      _targets = maps.map((m) => SyncTarget.fromMap(m)).toList();
      await _loadUsageCounts();
      if (refreshStatuses) {
        await refreshAllStatuses();
      }
    } catch (e) {
      _error = '加载目标失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUsageCounts() async {
    _usageMap.clear();
    for (final target in _targets) {
      _usageMap[target.id] = await _db.countTasksByTarget(target.id);
    }
  }

  Future<SyncTarget?> addTarget(SyncTarget target) async {
    try {
      await _db.insertTarget(target.toMap());
      _targets.insert(0, target);
      _usageMap[target.id] = 0;
      notifyListeners();
      return target;
    } catch (e) {
      _error = '添加目标失败: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateTarget(SyncTarget target) async {
    try {
      target.updatedAt = DateTime.now();
      await _db.updateTarget(target.id, target.toMap());
      final index = _targets.indexWhere((t) => t.id == target.id);
      if (index != -1) {
        _targets[index] = target;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = '更新目标失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteTarget(String targetId) async {
    try {
      final usageCount = usageCountOf(targetId);
      if (usageCount > 0) {
        _error = '该目标已被 $usageCount 个任务使用，请先修改任务再删除';
        notifyListeners();
        return false;
      }

      await _db.deleteTarget(targetId);
      _targets.removeWhere((t) => t.id == targetId);
      _statusMap.remove(targetId);
      _usageMap.remove(targetId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '删除目标失败: $e';
      notifyListeners();
      return false;
    }
  }

  SyncTarget? getTarget(String? targetId) {
    if (targetId == null) return null;
    try {
      return _targets.firstWhere((t) => t.id == targetId);
    } catch (_) {
      return null;
    }
  }

  Future<TargetStatusInfo> refreshTargetStatus(String targetId) async {
    final target = getTarget(targetId);
    if (target == null) {
      const status = TargetStatusInfo(
        state: TargetOnlineState.offline,
        message: '目标不存在',
      );
      _statusMap[targetId] = status;
      notifyListeners();
      return status;
    }

    _statusMap[targetId] = const TargetStatusInfo(
      state: TargetOnlineState.checking,
      message: '检测中...',
    );
    notifyListeners();

    final status = await checkTargetOnline(target);
    _statusMap[targetId] = status;
    notifyListeners();
    return status;
  }

  Future<void> refreshAllStatuses() async {
    if (_targets.isEmpty || _isRefreshingStatuses) return;

    _isRefreshingStatuses = true;
    try {
      final targets = List<SyncTarget>.from(_targets);
      for (final target in targets) {
        _statusMap[target.id] = const TargetStatusInfo(
          state: TargetOnlineState.checking,
          message: '检测中...',
        );
      }
      notifyListeners();

      final results = await Future.wait(targets.map(checkTargetOnline));
      for (var i = 0; i < targets.length; i++) {
        _statusMap[targets[i].id] = results[i];
      }
      notifyListeners();
    } finally {
      _isRefreshingStatuses = false;
    }
  }

  void startAutoRefresh({
    Duration interval = const Duration(seconds: 30),
    bool refreshImmediately = false,
  }) {
    _statusRefreshInterval = interval;
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = Timer.periodic(interval, (_) {
      refreshAllStatuses();
    });

    if (refreshImmediately) {
      refreshAllStatuses();
    }
  }

  void stopAutoRefresh() {
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = null;
  }

  Future<TargetStatusInfo> checkTargetOnline(
    SyncTarget target, {
    String? probePath,
    bool strictCredentialCheck = false,
  }) async {
    final now = DateTime.now();
    try {
      if (target.remoteProtocol == RemoteProtocol.webdav) {
        final effectiveProbePath = _normalizeProbePath(
          probePath ?? _defaultWebDavProbePath,
        );
        final task = SyncTask(
          name: 'target-check',
          localPath: '.',
          remoteProtocol: target.remoteProtocol,
          remoteHost: target.remoteHost,
          remotePort: target.remotePort,
          remoteUsername: target.remoteUsername,
          remotePassword: target.remotePassword,
          remotePath: effectiveProbePath,
        );

        final result = await _webdavService.testConnection(task);
        if (result.success) {
          return TargetStatusInfo(
            state: TargetOnlineState.online,
            message: '在线',
            lastCheckedAt: now,
          );
        }
        return TargetStatusInfo(
          state: TargetOnlineState.offline,
          message: result.error ?? '离线',
          lastCheckedAt: now,
        );
      }

      if (target.remoteProtocol == RemoteProtocol.smb) {
        final result = await _smbService.testConnection(
          host: target.remoteHost,
          port: target.remotePort,
          username: target.remoteUsername,
          password: target.remotePassword,
          strictCredentialCheck: strictCredentialCheck,
        );

        if (result.success) {
          return TargetStatusInfo(
            state: TargetOnlineState.online,
            message: strictCredentialCheck ? 'SMB 认证成功' : '在线',
            lastCheckedAt: now,
          );
        }

        return TargetStatusInfo(
          state: TargetOnlineState.offline,
          message: result.error ?? '离线',
          lastCheckedAt: now,
        );
      }

      final socket = await Socket.connect(
        target.remoteHost,
        target.remotePort,
        timeout: const Duration(seconds: 4),
      );
      await socket.close();

      return TargetStatusInfo(
        state: TargetOnlineState.online,
        message: '在线',
        lastCheckedAt: now,
      );
    } catch (e) {
      return TargetStatusInfo(
        state: TargetOnlineState.offline,
        message: '连接失败: $e',
        lastCheckedAt: now,
      );
    }
  }

  String normalizeTaskRemotePath(String value) {
    return _normalizePath(value, defaultPath: '/');
  }

  String? validateTaskRemotePath({
    required SyncTarget? target,
    required String remotePath,
  }) {
    if (target == null) {
      return null;
    }

    final normalized = normalizeTaskRemotePath(remotePath);
    if (target.remoteProtocol == RemoteProtocol.smb &&
        !_isValidSmbTaskRemotePath(normalized)) {
      return 'SMB 任务目标路径必须包含共享名，例如 /public 或 /public/folder';
    }

    return null;
  }

  String convertWindowsSelectedPathToSmbTaskRemotePath({
    required String selectedPath,
    required SyncTarget target,
  }) {
    final raw = selectedPath.trim();
    if (raw.isEmpty) {
      throw Exception('路径为空，请重新选择。');
    }

    final normalizedSlash = raw.replaceAll('\\', '/');
    final uncPattern = RegExp(r'^[\\/]{2}([^\\/]+)[\\/]+(.+)$');
    final match = uncPattern.firstMatch(normalizedSlash);

    if (match == null) {
      throw Exception(
        '请选择 UNC 网络路径，例如 \\\\${target.remoteHost}\\share\\folder',
      );
    }

    final selectedHost = (match.group(1) ?? '').trim();
    final pathRest = (match.group(2) ?? '').trim();
    if (selectedHost.isEmpty || pathRest.isEmpty) {
      throw Exception('UNC 路径不完整，请选择到共享目录下。');
    }

    if (selectedHost.toLowerCase() != target.remoteHost.toLowerCase()) {
      throw Exception('所选主机为 $selectedHost，与当前目标 ${target.remoteHost} 不一致。');
    }

    final segments = pathRest
        .split(RegExp(r'[\\/]+'))
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      throw Exception('未识别到共享名，请重新选择。');
    }

    return '/${segments.join('/')}';
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    unawaited(_smbService.disconnect());
    super.dispose();
  }

  String _normalizeProbePath(String? value) {
    return _normalizePath(value, defaultPath: '/');
  }

  bool _isValidSmbTaskRemotePath(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    return segments.isNotEmpty;
  }

  String _normalizePath(String? value, {required String defaultPath}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return defaultPath;
    final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return withLeadingSlash.replaceAll(RegExp(r'/+'), '/');
  }
}
