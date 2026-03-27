//! 仓库相关数据模型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

/// 已注册仓库（软件级数据库）
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct RegisteredRepository {
    pub id: i64,
    pub local_path: String,
    pub name: String,
    pub last_accessed: Option<DateTime<Utc>>,
    pub added_at: DateTime<Utc>,
}

/// 新仓库请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterRepositoryRequest {
    pub local_path: String,
    pub name: String,
    pub bind_default_remote: Option<i64>,  // 远程连接ID
}

/// 仓库绑定远端配置（存储在仓库内）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryRemote {
    pub remote_name: String,
    pub connection_id: i64,  // 引用软件级远程连接
    pub remote_path: String,
    pub is_default: bool,
    pub last_sync: Option<DateTime<Utc>>,
    pub last_fetch: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// 仓库本地设置（存储在仓库内）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryLocalSettings {
    pub max_versions: Option<i32>,
    pub max_version_days: Option<i32>,
    pub max_version_size_gb: Option<i32>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Default for RepositoryLocalSettings {
    fn default() -> Self {
        let now = Utc::now();
        Self {
            max_versions: Some(100),
            max_version_days: Some(365),
            max_version_size_gb: Some(10),
            created_at: now,
            updated_at: now,
        }
    }
}

/// 仓库状态摘要
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryStatus {
    pub repository_id: i64,
    pub repository_name: String,
    pub local_path: String,
    pub default_remote_name: Option<String>,
    pub ahead: i32,
    pub behind: i32,
    pub is_dirty: bool,
    pub has_staged_changes: bool,
    pub has_unstaged_changes: bool,
    pub has_conflicts: bool,
    pub current_branch: Option<String>,
    pub last_sync: Option<DateTime<Utc>>,
    pub last_fetch: Option<DateTime<Utc>>,
}

/// 仓库导入选项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportRepositoryOptions {
    pub path: String,
    pub name: Option<String>,
    pub bind_remote_id: Option<i64>,
    pub bind_remote_path: Option<String>,
    pub settings: Option<RepositoryLocalSettings>,
}

/// 仓库克隆选项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloneRepositoryOptions {
    pub remote_connection_id: i64,
    pub remote_path: String,
    pub local_path: String,
    pub name: Option<String>,
}

/// 仓库迁移选项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrateRepositoryOptions {
    pub repository_id: i64,
    pub new_local_path: String,
}

/// 仓库删除选项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteRepositoryOptions {
    pub repository_id: i64,
    pub delete_nanosync_folder: bool,
}

/// 远端绑定请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BindRemoteRequest {
    pub repository_id: i64,
    pub connection_id: i64,
    pub remote_name: String,
    pub remote_path: String,
    pub is_default: bool,
}

/// 仓库配置文件（存储在 .nanosync/config.json）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryConfig {
    pub id: i64,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub device_fingerprint: String,
    pub default_remote_name: Option<String>,
}

/// 仓库状态文件（存储在 .nanosync/repository_state.json）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryState {
    pub head_commit_id: String,
    pub current_branch: String,
    pub branches: Vec<BranchState>,
    pub last_export: Option<DateTime<Utc>>,
}

/// 分支状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchState {
    pub name: String,
    pub head_commit_id: String,
    pub is_default: bool,
}

/// 远端跟踪状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteTrackingState {
    pub remote_name: String,
    pub head_commit_id: String,
    pub last_fetch: Option<DateTime<Utc>>,
}
