//! 数据库 Schema 定义
//!
//! 软件级数据库只包含远程连接和已注册仓库两张表

/// 软件级数据库 Schema
pub const APP_DB_SCHEMA: &str = r#"
-- 已注册仓库表
CREATE TABLE IF NOT EXISTS registered_repositories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    local_path TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    last_accessed TEXT,
    added_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_registered_repositories_path ON registered_repositories(local_path);
CREATE INDEX IF NOT EXISTS idx_registered_repositories_name ON registered_repositories(name);

-- 远程连接表
CREATE TABLE IF NOT EXISTS remote_connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    protocol TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER,
    username TEXT,
    password TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_remote_connections_name ON remote_connections(name);
CREATE INDEX IF NOT EXISTS idx_remote_connections_protocol ON remote_connections(protocol);

-- 数据库版本表
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"#;

/// 仓库级数据库 Schema
pub const REPOSITORY_DB_SCHEMA: &str = r#"
-- 仓库配置表
CREATE TABLE IF NOT EXISTS repository_config (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    name TEXT NOT NULL,
    device_fingerprint TEXT NOT NULL,
    default_remote_name TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 分支表
CREATE TABLE IF NOT EXISTS branches (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    head_commit_id TEXT,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_branches_repository ON branches(repository_id);
CREATE INDEX IF NOT EXISTS idx_branches_name ON branches(name);

-- 提交表
CREATE TABLE IF NOT EXISTS commits (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    branch_name TEXT NOT NULL,
    parent_ids TEXT NOT NULL,  -- JSON array
    message TEXT NOT NULL,
    author TEXT NOT NULL,
    author_email TEXT,
    timestamp TEXT NOT NULL,
    tree_root TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_commits_repository ON commits(repository_id);
CREATE INDEX IF NOT EXISTS idx_commits_branch ON commits(branch_name);
CREATE INDEX IF NOT EXISTS idx_commits_timestamp ON commits(timestamp);

-- 树条目表
CREATE TABLE IF NOT EXISTS tree_entries (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    entry_type TEXT NOT NULL,
    object_id TEXT NOT NULL,
    mode TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tree_entries_object ON tree_entries(object_id);

-- 文件变更表
CREATE TABLE IF NOT EXISTS file_changes (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    commit_id TEXT,
    path TEXT NOT NULL,
    old_path TEXT,
    change_type TEXT NOT NULL,
    old_hash TEXT,
    new_hash TEXT,
    old_size INTEGER,
    new_size INTEGER
);

CREATE INDEX IF NOT EXISTS idx_file_changes_repository ON file_changes(repository_id);
CREATE INDEX IF NOT EXISTS idx_file_changes_commit ON file_changes(commit_id);
CREATE INDEX IF NOT EXISTS idx_file_changes_path ON file_changes(path);

-- 暂存区表
CREATE TABLE IF NOT EXISTS staging_entries (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    path TEXT NOT NULL,
    object_id TEXT,
    change_type TEXT NOT NULL,
    staged_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(repository_id, path)
);

CREATE INDEX IF NOT EXISTS idx_staging_repository ON staging_entries(repository_id);

-- Stash 表
CREATE TABLE IF NOT EXISTS stashes (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    name TEXT,
    message TEXT,
    commit_id TEXT NOT NULL,
    branch_name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_stashes_repository ON stashes(repository_id);

-- Stash 条目表
CREATE TABLE IF NOT EXISTS stash_entries (
    id TEXT PRIMARY KEY,
    stash_id TEXT NOT NULL,
    path TEXT NOT NULL,
    object_id TEXT NOT NULL,
    change_type TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_stash_entries_stash ON stash_entries(stash_id);

-- 仓库远端绑定表
CREATE TABLE IF NOT EXISTS repository_remotes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    remote_name TEXT NOT NULL,
    connection_id INTEGER NOT NULL,  -- 引用软件级数据库的 remote_connections.id
    remote_path TEXT NOT NULL,
    is_default INTEGER NOT NULL DEFAULT 0,
    last_sync TEXT,
    last_fetch TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(repository_id, remote_name)
);

CREATE INDEX IF NOT EXISTS idx_repo_remotes_repository ON repository_remotes(repository_id);
CREATE INDEX IF NOT EXISTS idx_repo_remotes_connection ON repository_remotes(connection_id);

-- 本地设置表
CREATE TABLE IF NOT EXISTS local_settings (
    repository_id INTEGER PRIMARY KEY,
    max_versions INTEGER,
    max_version_days INTEGER,
    max_version_size_gb INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 自动化规则表
CREATE TABLE IF NOT EXISTS automation_rules (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    trigger_type TEXT NOT NULL,
    action_type TEXT NOT NULL,
    trigger_config TEXT,  -- JSON
    enabled INTEGER NOT NULL DEFAULT 1,
    owner_device_fingerprint TEXT NOT NULL,
    is_imported INTEGER NOT NULL DEFAULT 0,
    last_triggered TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    retry_delay_seconds INTEGER NOT NULL DEFAULT 60,
    debounce_seconds INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_automation_repository ON automation_rules(repository_id);
CREATE INDEX IF NOT EXISTS idx_automation_enabled ON automation_rules(enabled);
CREATE INDEX IF NOT EXISTS idx_automation_owner ON automation_rules(owner_device_fingerprint);

-- 自动化执行记录表
CREATE TABLE IF NOT EXISTS automation_executions (
    id TEXT PRIMARY KEY,
    rule_id TEXT NOT NULL,
    repository_id INTEGER NOT NULL,
    device_fingerprint TEXT NOT NULL,
    device_name TEXT NOT NULL,
    trigger_type TEXT NOT NULL,
    action_type TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT,
    status TEXT NOT NULL,
    error_message TEXT,
    retry_attempt INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_executions_rule ON automation_executions(rule_id);
CREATE INDEX IF NOT EXISTS idx_executions_repository ON automation_executions(repository_id);
CREATE INDEX IF NOT EXISTS idx_executions_status ON automation_executions(status);

-- 同步日志表
CREATE TABLE IF NOT EXISTS sync_logs (
    id TEXT PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    device_fingerprint TEXT NOT NULL,
    device_name TEXT NOT NULL,
    sync_type TEXT NOT NULL,
    remote_name TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT,
    total_files INTEGER NOT NULL DEFAULT 0,
    success_count INTEGER NOT NULL DEFAULT 0,
    fail_count INTEGER NOT NULL DEFAULT 0,
    skip_count INTEGER NOT NULL DEFAULT 0,
    conflict_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    error_message TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sync_logs_repository ON sync_logs(repository_id);
CREATE INDEX IF NOT EXISTS idx_sync_logs_start_time ON sync_logs(start_time);

-- 应用日志表
CREATE TABLE IF NOT EXISTS app_logs (
    id TEXT PRIMARY KEY,
    repository_id INTEGER,
    device_fingerprint TEXT NOT NULL,
    device_name TEXT NOT NULL,
    username TEXT NOT NULL,
    level TEXT NOT NULL,
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    details TEXT,
    source TEXT,
    context TEXT,  -- JSON
    stack_trace TEXT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_logs_repository ON app_logs(repository_id);
CREATE INDEX IF NOT EXISTS idx_logs_level ON app_logs(level);
CREATE INDEX IF NOT EXISTS idx_logs_category ON app_logs(category);
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON app_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_device ON app_logs(device_fingerprint);

-- 远端跟踪状态表
CREATE TABLE IF NOT EXISTS remote_tracking (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    remote_name TEXT NOT NULL,
    tracked_branch TEXT,
    last_fetch TEXT,
    head_commit_id TEXT,
    UNIQUE(repository_id, remote_name)
);

CREATE INDEX IF NOT EXISTS idx_remote_tracking_repository ON remote_tracking(repository_id);

-- 数据库版本表
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"#;

/// 当前数据库版本
pub const CURRENT_SCHEMA_VERSION: i32 = 1;