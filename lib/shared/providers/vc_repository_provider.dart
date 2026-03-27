import 'package:flutter/foundation.dart';
import '../../data/models/vc_models.dart';
import '../../data/services/vc_engine.dart';
import '../../data/vc_database.dart';

class VcRepositoryProvider extends ChangeNotifier {
  final VcDatabase _db = VcDatabase.instance;

  List<VcRepository> _repositories = [];
  VcRepository? _currentRepository;
  VcEngine? _currentEngine;
  VcRepositoryStatus? _status;

  List<VcRepository> get repositories => _repositories;
  VcRepository? get currentRepository => _currentRepository;
  VcEngine? get currentEngine => _currentEngine;
  VcRepositoryStatus? get status => _status;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> loadRepositories() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _repositories = await _db.getAllRepositories();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<VcOperationResultData> createRepository({
    required String name,
    required String localPath,
    String initialBranch = 'main',
    List<String> ignoreRules = const [],
  }) async {
    try {
      final repo = VcRepository(name: name, localPath: localPath);

      await _db.insertRepository(repo.toMap());

      _currentRepository = repo;
      _currentEngine = VcEngine(repositoryId: repo.id);

      final branchName = initialBranch.trim().isEmpty
          ? 'main'
          : initialBranch.trim();
      final initResult = await _currentEngine!.init(
        name: branchName,
        ignoreRules: ignoreRules,
      );
      if (initResult.isSuccess) {
        await loadRepositories();
        await loadStatus();
        return initResult;
      } else {
        _error = initResult.message;
        notifyListeners();
        return initResult;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: e.toString(),
      );
    }
  }

  Future<void> selectRepository(String repositoryId) async {
    try {
      final repo = await _db.getRepository(repositoryId);
      if (repo != null) {
        _currentRepository = repo;
        _currentEngine = VcEngine(repositoryId: repo.id);
        await loadStatus();
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadStatus() async {
    if (_currentEngine == null) return;

    try {
      final result = await _currentEngine!.status();
      if (result.isSuccess) {
        _status = result.data as VcRepositoryStatus;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<VcOperationResultData> add({
    List<String>? files,
    bool all = false,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.add(files: files, all: all);
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> commit({
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.commit(
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
    );
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> reset({
    List<String>? files,
    bool all = false,
    bool hard = false,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.reset(
      files: files,
      all: all,
      hard: hard,
    );
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> branch({
    required String name,
    String? commitId,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.branch(name: name, commitId: commitId);
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> checkout({
    String? branchName,
    String? commitId,
    bool create = false,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.checkout(
      branchName: branchName,
      commitId: commitId,
      create: create,
    );
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> revert({
    required String commitId,
    bool noCommit = false,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.revert(
      commitId: commitId,
      noCommit: noCommit,
    );
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> stash({
    String? message,
    bool includeUntracked = false,
  }) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.stash(
      message: message,
      includeUntracked: includeUntracked,
    );
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> stashPop({String? stashId}) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.stashPop(stashId: stashId);
    await loadStatus();
    return result;
  }

  Future<List<VcCommit>> log({String? branchId, int? limit}) async {
    if (_currentEngine == null) return [];
    return await _currentEngine!.log(branchId: branchId, limit: limit);
  }

  Future<List<VcBranch>> listBranches() async {
    if (_currentEngine == null) return [];
    return await _currentEngine!.listBranches();
  }

  Future<List<VcStash>> listStashes() async {
    if (_currentEngine == null) return [];
    return await _currentEngine!.listStashes();
  }

  Future<List<VcStagingEntry>> getStagedChanges() async {
    if (_currentEngine == null) return [];
    return await _currentEngine!.getStagedChanges();
  }

  Future<List<VcFileChange>> getUnstagedChanges() async {
    if (_currentEngine == null) return [];
    return await _currentEngine!.getUnstagedChanges();
  }

  Future<List<VcFileDiff>> diff({
    String? commitId1,
    String? commitId2,
    bool cached = false,
  }) async {
    if (_currentEngine == null) return [];
    return await _currentEngine!.diff(
      commitId1: commitId1,
      commitId2: commitId2,
      cached: cached,
    );
  }

  Future<VcOperationResultData> deleteBranch(String branchName) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.deleteBranch(branchName);
    await loadStatus();
    return result;
  }

  Future<VcOperationResultData> deleteStash(String stashId) async {
    if (_currentEngine == null) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'No repository selected',
      );
    }

    final result = await _currentEngine!.deleteStash(stashId);
    await loadStatus();
    return result;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
