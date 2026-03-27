# NanoSync 架构重构计划：纯 Git 风格版本控制系统

## 一、设计目标

### 1.1 核心理念

- **仓库为中心**：移除 Job 概念，以 Repository（仓库）为核心实体
- **Git 风格操作**：fetch/push/pull/clone，无方向性同步
- **完整历史同步**：同步 `.nanosync/` 整个目录，支持跨设备完整历史恢复
- **配置跟随仓库**：仓库配置存储在 `.nanosync/` 内，可随仓库迁移

### 1.2 架构对比

| 维度 | 旧架构 | 新架构 |
|------|--------|--------|
| 核心实体 | Job（同步任务） | Repository（仓库） |
| 远程配置 | Job 关联一个 Target | Repository 可有多个 Remote |
| 配置存储 | 数据库 + Job 对象 | `.nanosync/config.json`（仓库内） |
| 敏感信息 | Job 中存储 | 软件本地数据库（不随仓库同步） |
| 历史限制 | 无 | 可配置数量/时间/大小 |
| 软件职责 | 管理所有配置 | 仅管理 repo 列表 + remote 连接信息 |

---

## 二、数据模型设计

### 2.1 仓库配置文件 (`.nanosync/config.json`)

存储在仓库根目录下，随仓库同步：

```json
{
  "version": 1,
  "name": "my-project",
  "description": "项目描述",
  "created_at": "2024-01-01T00:00:00Z",
  "default_branch": "main",
  "remotes": ["nas-backup", "cloud-sync"],
  "history": {
    "max_count": 100,
    "max_days": 365,
    "max_size_mb": 1024
  },
  "auto_sync": {
    "enabled": true,
    "interval_minutes": 30,
    "remote": "nas-backup",
    "action": "sync"
  },
  "ignore": {
    "patterns": [".git/", "node_modules/", "*.tmp"],
    "extensions": [".log", ".bak"],
    "folders": [".vscode", "dist"]
  }
}
```

### 2.2 软件本地存储

软件本地数据库仅存储：

#### 2.2.1 仓库注册表 (`registered_repositories`)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 仓库 ID（与 .nanosync 中一致） |
| local_path | TEXT | 本地路径 |
| name | TEXT | 仓库名称（便于显示） |
| last_accessed | TEXT | 最后访问时间 |
| added_at | TEXT | 添加时间 |

#### 2.2.2 远程连接配置 (`remote_connections`)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 连接 ID |
| name | TEXT | 名称（如 "nas-backup"） |
| protocol | TEXT | smb / webdav |
| host | TEXT | 主机地址 |
| port | INTEGER | 端口 |
| username | TEXT | 用户名 |
| password | TEXT | 密码（加密存储） |
| created_at | TEXT | 创建时间 |
| updated_at | TEXT | 更新时间 |

#### 2.2.3 仓库-远程关联 (`repository_remotes`)

| 字段 | 类型 | 说明 |
|------|------|------|
| repository_id | TEXT | 仓库 ID |
| remote_name | TEXT | 远程名称 |
| remote_path | TEXT | 远程仓库路径 |
| is_default | INTEGER | 是否默认远程 |
| last_sync | TEXT | 最后同步时间 |
| last_fetch | TEXT | 最后 fetch 时间 |

### 2.3 远程仓库结构

```
remote://path/
├── .nanosync/
│   ├── config.json              # 仓库配置
│   ├── repository_state.json    # 完整仓库元数据
│   ├── objects/                 # 文件历史版本对象
│   │   ├── abc123...           # 文件内容快照（hash 作为文件名）
│   │   └── def456...
│   ├── refs/                    # 引用
│   │   └── heads/
│   │       └── main
│   └── staging/                 # 暂存区（不同步）
├── <工作目录文件...>
```

---

## 三、核心组件设计

### 3.1 仓库管理器 (RepositoryManager)

```dart
class RepositoryManager {
  /// 注册本地仓库（添加到软件管理）
  Future<Repository> registerRepository(String localPath);
  
  /// 注销仓库（从软件移除，不删除文件）
  Future<void> unregisterRepository(String repositoryId);
  
  /// 获取所有已注册仓库
  Future<List<Repository>> listRepositories();
  
  /// 导入既有文件夹为仓库
  Future<Repository> importExisting(
    String localPath, {
    bool initialCommit = false,
    String? remoteName,
    String? remotePath,
  });
  
  /// 从远程克隆仓库
  Future<Repository> clone({
    required RemoteConnection remote,
    required String remotePath,
    required String localPath,
  });
}
```

### 3.2 远程连接管理器 (RemoteConnectionManager)

```dart
class RemoteConnectionManager {
  /// 添加远程连接配置
  Future<RemoteConnection> addConnection(RemoteConnection connection);
  
  /// 更新连接配置
  Future<void> updateConnection(RemoteConnection connection);
  
  /// 删除连接配置
  Future<void> removeConnection(String connectionId);
  
  /// 获取所有连接
  Future<List<RemoteConnection>> listConnections();
  
  /// 测试连接
  Future<ConnectionTestResult> testConnection(String connectionId);
  
  /// 绑定远程到仓库
  Future<void> bindToRepository({
    required String repositoryId,
    required String connectionName,
    required String remotePath,
    bool isDefault = false,
  });
}
```

### 3.3 同步引擎 (SyncEngine) - 重构

```dart
class SyncEngine {
  /// 获取远端状态（不修改本地）
  Future<FetchResult> fetch(Repository repo, {String? remoteName});
  
  /// 推送本地变更到远端
  Future<PushResult> push(Repository repo, {String? remoteName, bool force = false});
  
  /// 拉取远端变更到本地
  Future<PullResult> pull(Repository repo, {String? remoteName, bool rebase = false});
  
  /// 完整同步
  Future<SyncResult> sync(Repository repo, {String? remoteName});
  
  /// 克隆远程仓库
  Future<Repository> clone(CloneOptions options);
}
```

### 3.4 历史清理器 (HistoryCleaner)

```dart
class HistoryCleaner {
  /// 清理超出限制的历史版本
  Future<CleanupResult> cleanup(Repository repo);
  
  /// 计算历史统计
  Future<HistoryStats> calculateStats(Repository repo);
  
  /// 检查是否需要清理
  bool needsCleanup(Repository repo, HistoryStats stats);
  
  /// 删除不再被引用的 objects
  Future<void> cleanupUnreferencedObjects(Repository repo);
}
```

---

## 四、同步流程详解

### 4.1 Fetch 流程

```
输入: Repository repo, String remoteName
输出: FetchResult { ahead, behind, remoteHead, hasUpdates }

1. 获取远程连接配置
2. 连接远程服务器
3. 下载 .nanosync/repository_state.json
4. 解析远程仓库状态
5. 对比本地与远程 commits：
   - ahead = 本地领先提交数
   - behind = 本地落后提交数
6. 更新 repository_remotes 表
7. 返回结果
```

### 4.2 Push 流程

```
输入: Repository repo, String remoteName
输出: PushResult { pushedCommits, pushedObjects, success }

1. fetch() 获取最新远程状态
2. 检查 behind > 0：
   - 如果有落后提交，提示需要先 pull
3. 收集需要推送的对象：
   - 遍历本地领先 commits
   - 收集关联的 tree_entries 中的 file_hash
4. 上传到远程：
   - 上传 objects/{hash} 文件（仅远程没有的）
   - 上传 .nanosync/config.json
   - 上传 .nanosync/repository_state.json
5. 触发历史清理（如果配置）
6. 返回结果
```

### 4.3 Pull 流程

```
输入: Repository repo, String remoteName, bool rebase
输出: PullResult { pulledCommits, mergedFiles, conflicts }

1. fetch() 获取最新远程状态
2. 下载远程 objects：
   - 计算本地缺失的对象 hash
   - 逐个下载到本地 objects/
3. 合并：
   - 如果 ahead = 0：fast-forward
   - 如果有本地变更：merge 或 rebase
4. 检出工作目录到新 HEAD
5. 触发历史清理（如果配置）
6. 返回结果
```

### 4.4 Clone 流程

```
输入: RemoteConnection remote, String remotePath, String localPath
输出: Repository

1. 创建本地目录
2. 下载远程 .nanosync/ 目录
3. 导入仓库元数据
4. 下载所有 objects
5. 检出工作目录到 HEAD
6. 注册到本地软件
7. 绑定远程连接信息
8. 返回 Repository
```

### 4.5 导入既有仓库流程

```
输入: String localPath, bool initialCommit, RemoteConnection remote, String remotePath
输出: Repository

1. 检查目录是否已有 .nanosync/
   - 如果有：直接注册，读取配置
   - 如果没有：
     a. 创建 .nanosync/ 目录结构
     b. 创建默认配置
     c. 如果 initialCommit=true：
        - 扫描所有文件
        - 创建初始提交
     d. 写入 config.json
2. 注册到本地软件
3. 如果提供了 remote：绑定远程连接
4. 返回 Repository
```

---

## 五、历史版本管理

### 5.1 配置项

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| max_count | int | 100 | 最大保留提交数量 |
| max_days | int | 365 | 最大保留天数 |
| max_size_mb | int | 1024 | objects 目录最大体积 (MB) |

### 5.2 清理策略

```dart
/// 任一条件超限即触发清理
bool shouldCleanup(HistoryConfig config, HistoryStats stats) {
  if (config.maxCount > 0 && stats.commitCount > config.maxCount) return true;
  if (config.maxDays > 0 && stats.oldestCommitAge > config.maxDays) return true;
  if (config.maxSizeMb > 0 && stats.objectsSizeMb > config.maxSizeMb) return true;
  return false;
}
```

### 5.3 清理流程

```
1. 获取历史配置
2. 计算当前统计
3. 判断是否需要清理
4. 如果需要：
   a. 找出要保留的 commits（最新 N 个 或 最近 N 天内）
   b. 删除其他 commits 及其关联的 file_changes
   c. 删除不再被引用的 tree_entries
   d. 清理 objects 目录：
      - 收集所有被引用的 file_hash
      - 删除未被引用的 objects 文件
5. 记录清理日志
```

---

## 六、UI 设计

### 6.1 主界面

```
┌─────────────────────────────────────────────────────────────────┐
│ NanoSync                                    [设置] [关于]       │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ [添加仓库] [从远程克隆]                    搜索: [______]   │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 📁 我的项目                              main ↑2 ↓0         │ │
│ │ C:\Projects\my-project                                     │ │
│ │ 远程: nas-backup (smb://nas.local/backup)                   │ │
│ │ 最后同步: 2024-01-15 14:30                  [Fetch] [Sync▶]│ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 📁 文档归档                              main ↑0 ↓3         │ │
│ │ D:\Documents\archive                                       │ │
│ │ 远程: cloud-sync (webdav://cloud.example.com/docs)         │ │
│ │ 需要拉取 3 个提交                           [Pull] [Fetch]  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 仓库详情页

```
┌─────────────────────────────────────────────────────────────────┐
│ ← 返回   我的项目                              [编辑] [历史]    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 状态: main ↑2 ↓0 (领先 2 个提交)                                │
│                                                                 │
│ [Fetch] [Push] [Pull] [Sync▶]                                  │
│                                                                 │
│ ───────────────────────────────────────────────────────────────│
│ 远程配置                                                        │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ nas-backup (默认)                  smb://nas.local:445     │ │
│ │ 路径: /backup/my-project          [测试] [编辑] [移除]      │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ cloud-sync                         webdav://cloud...       │ │
│ │ 路径: /docs/project               [设为默认] [编辑] [移除]   │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ [+ 添加远程]                                                    │
│                                                                 │
│ ───────────────────────────────────────────────────────────────│
│ 历史配置                                                        │
│                                                                 │
│ 最大提交数: [100    ]  最大天数: [365    ]  最大体积: [1024  ] MB│
│                                                                 │
│ 当前统计: 45 个提交, 234 MB, 最老 30 天                         │
│                                                                 │
│ [立即清理]                                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 远程连接管理页

```
┌─────────────────────────────────────────────────────────────────┐
│ ← 返回   远程连接管理                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ [+ 新建连接]                                                    │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ nas-backup                              SMB                  │ │
│ │ smb://nas.local:445                    [测试] [编辑] [删除]  │ │
│ │ 用户: admin                                                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ cloud-sync                              WebDAV               │ │
│ │ webdav://cloud.example.com:443         [测试] [编辑] [删除]  │ │
│ │ 用户: user@example.com                                      │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 添加仓库向导

```
步骤 1: 选择方式
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│ 如何添加仓库？                                                   │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 📂 导入本地文件夹                                           │ │
│ │ 选择已有的本地文件夹作为仓库                                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ⬇️ 从远程克隆                                               │ │
│ │ 从远程服务器克隆现有仓库                                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

步骤 2a: 导入本地文件夹
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│ 本地路径: [C:\Projects\my-project                    ] [选择]   │
│                                                                 │
│ 仓库名称: [我的项目                                   ]         │
│                                                                 │
│ ☑ 将现有文件作为初始提交                                         │
│                                                                 │
│ ───────────────────────────────────────────────────────────────│
│ 远程配置（可选）                                                 │
│                                                                 │
│ 连接: [nas-backup        ▼]                                     │
│ 远程路径: [/backup/my-project    ]                              │
│                                                                 │
│ [取消]                                           [创建仓库]     │
└─────────────────────────────────────────────────────────────────┘

步骤 2b: 从远程克隆
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│ 远程连接: [cloud-sync        ▼]                                │
│                                                                 │
│ 远程路径: [/docs/my-project      ]                              │
│                                                                 │
│ 本地路径: [C:\Projects\my-project                    ] [选择]   │
│                                                                 │
│ [取消]                                             [克隆]       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 七、数据库设计

### 7.1 软件本地数据库 (`nanosync.db`)

```sql
-- 仓库注册表
CREATE TABLE registered_repositories (
  id TEXT PRIMARY KEY,
  local_path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  last_accessed TEXT,
  added_at TEXT NOT NULL
);

CREATE INDEX idx_repos_path ON registered_repositories(local_path);
CREATE INDEX idx_repos_name ON registered_repositories(name);

-- 远程连接配置
CREATE TABLE remote_connections (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  username TEXT NOT NULL DEFAULT '',
  password TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX idx_connections_name ON remote_connections(name);

-- 仓库-远程关联
CREATE TABLE repository_remotes (
  id TEXT PRIMARY KEY,
  repository_id TEXT NOT NULL,
  remote_name TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0,
  last_sync TEXT,
  last_fetch TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (repository_id) REFERENCES registered_repositories(id) ON DELETE CASCADE,
  FOREIGN KEY (remote_name) REFERENCES remote_connections(name) ON DELETE CASCADE,
  UNIQUE(repository_id, remote_name)
);

CREATE INDEX idx_repo_remotes_repo ON repository_remotes(repository_id);
```

### 7.2 仓库数据库 (`.nanosync/nanosync.db`)

每个仓库独立的数据库，存储版本控制信息：

```sql
-- 与现有 vc_database.dart 结构一致
-- vc_repositories, vc_branches, vc_commits, vc_tree_entries, 
-- vc_file_changes, vc_staging_entries, vc_stashes, vc_remotes, vc_sync_records
```

---

## 八、文件变更清单

### 8.1 新增文件

| 文件路径 | 说明 |
|----------|------|
| `lib/data/models/repository_config.dart` | 仓库配置模型 |
| `lib/data/models/remote_connection.dart` | 远程连接模型 |
| `lib/data/models/sync_result.dart` | 同步结果模型 |
| `lib/data/models/history_config.dart` | 历史配置模型 |
| `lib/data/services/repository_manager.dart` | 仓库管理器 |
| `lib/data/services/remote_connection_manager.dart` | 远程连接管理器 |
| `lib/data/services/history_cleaner.dart` | 历史清理器 |
| `lib/features/repository/repository_list_page.dart` | 仓库列表页 |
| `lib/features/repository/repository_detail_page.dart` | 仓库详情页 |
| `lib/features/repository/add_repository_wizard.dart` | 添加仓库向导 |
| `lib/features/remote/remote_connections_page.dart` | 远程连接管理页 |
| `lib/shared/providers/repository_provider.dart` | 仓库 Provider |

### 8.2 修改文件

| 文件路径 | 变更说明 |
|----------|----------|
| `lib/core/constants/enums.dart` | 移除 SyncDirection，新增 SyncAction |
| `lib/data/services/sync_engine.dart` | 重构为 fetch/push/pull/sync |
| `lib/data/services/vc_sync_service.dart` | 增强 objects 同步 |
| `lib/data/services/vc_engine.dart` | 新增 fetch/push/pull/clone |
| `lib/data/services/smb_service.dart` | 新增目录同步方法 |
| `lib/data/services/webdav_service.dart` | 新增目录同步方法 |
| `lib/data/database/database_helper.dart` | 新表结构 + 迁移 |
| `lib/data/vc_database.dart` | 新字段 |
| `lib/main.dart` | 更新入口页面 |
| `lib/shared/widgets/app_shell.dart` | 更新导航结构 |

### 8.3 删除文件

| 文件路径 | 说明 |
|----------|------|
| `lib/data/models/sync_task.dart` | 移除 Job 概念 |
| `lib/data/models/sync_target.dart` | 移除 Target 概念 |
| `lib/features/task_management/*` | 移除任务管理相关页面 |
| `lib/shared/providers/task_provider.dart` | 移除任务 Provider |
| `lib/shared/providers/target_provider.dart` | 移除目标 Provider |

---

## 九、迁移策略

### 9.1 数据迁移

对于已存在的旧版本数据：

```dart
Future<void> migrateFromOldVersion(Database db) async {
  // 检查旧表是否存在
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_tasks'"
  );
  
  if (tables.isEmpty) return;
  
  // 读取旧任务
  final tasks = await db.query('sync_tasks');
  
  for (final task in tasks) {
    final localPath = task['local_path'] as String;
    
    // 创建仓库配置
    final config = RepositoryConfig(
      name: task['name'] as String,
      history: HistoryConfig(
        maxCount: 100,
        maxDays: 365,
        maxSizeMb: 1024,
      ),
    );
    
    // 写入 .nanosync/config.json
    await writeRepositoryConfig(localPath, config);
    
    // 注册仓库
    await db.insert('registered_repositories', {
      'id': task['id'],
      'local_path': localPath,
      'name': task['name'],
      'added_at': task['created_at'],
    });
    
    // 如果有远程配置，创建连接
    if (task['target_id'] != null) {
      final target = await getTarget(task['target_id']);
      if (target != null) {
        // 创建远程连接
        await db.insert('remote_connections', {
          'id': target['id'],
          'name': target['name'],
          'protocol': target['remote_protocol'],
          'host': target['remote_host'],
          'port': target['remote_port'],
          'username': target['remote_username'],
          'password': target['remote_password'],
        });
        
        // 创建关联
        await db.insert('repository_remotes', {
          'repository_id': task['id'],
          'remote_name': target['name'],
          'remote_path': task['remote_path'],
          'is_default': 1,
        });
      }
    }
  }
  
  // 删除旧表（可选，或保留）
  // await db.execute('DROP TABLE sync_tasks');
  // await db.execute('DROP TABLE sync_targets');
}
```

### 9.2 版本兼容

- 新版本可读取旧版本创建的 `.nanosync/` 目录
- 自动将旧版本仓库配置迁移到新格式
- 提供迁移向导帮助用户平滑升级

---

## 十、开发计划

### Phase 1: 核心模型重构 (3-5 天)

1. 实现新的数据模型
2. 重构数据库结构
3. 实现仓库配置读写
4. 实现远程连接管理

### Phase 2: 同步引擎重构 (5-7 天)

1. 重构 SyncEngine (fetch/push/pull/sync)
2. 增强 VcSyncService
3. 实现历史清理器
4. 完善 objects 同步

### Phase 3: 仓库管理 (3-4 天)

1. 实现 RepositoryManager
2. 实现导入既有仓库
3. 实现克隆功能
4. 实现自动同步

### Phase 4: UI 重构 (5-7 天)

1. 新建仓库相关页面
2. 新建远程连接管理页面
3. 重构主界面
4. 实现添加仓库向导

### Phase 5: 测试与优化 (3-5 天)

1. 单元测试
2. 集成测试
3. 性能优化
4. 文档更新

---

## 十一、风险与注意事项

### 11.1 数据安全

- 密码等敏感信息存储在软件本地，不上传到远程
- 远程仓库 `.nanosync/` 目录可能包含敏感配置，需注意访问控制

### 11.2 向后兼容

- 提供旧版本数据迁移工具
- 新版本可读取旧版本仓库，但建议用户升级

### 11.3 性能考虑

- 大量 objects 文件可能导致同步缓慢
- 历史清理需要高效算法
- 大仓库的 fetch/push/pull 需要增量处理

### 11.4 网络异常

- 断点续传支持
- 网络超时处理
- 部分同步失败恢复
