//! 同步相关数据模型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::str::FromStr;

/// 同步类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncType {
    Fetch,
    Push,
    Pull,
    Sync,
}

/// 同步状态
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncStatus {
    Pending,
    Running,
    Success,
    PartialSuccess,
    Failed,
    Cancelled,
}

/// 冲突解决策略
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConflictResolution {
    Ours,
    Theirs,
    Both,
    Manual,
}

impl fmt::Display for SyncType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SyncType::Fetch => write!(f, "fetch"),
            SyncType::Push => write!(f, "push"),
            SyncType::Pull => write!(f, "pull"),
            SyncType::Sync => write!(f, "sync"),
        }
    }
}

impl FromStr for SyncType {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "fetch" => Ok(SyncType::Fetch),
            "push" => Ok(SyncType::Push),
            "pull" => Ok(SyncType::Pull),
            "sync" => Ok(SyncType::Sync),
            _ => Err(format!("Unknown sync type: {}", s)),
        }
    }
}

impl fmt::Display for SyncStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SyncStatus::Pending => write!(f, "pending"),
            SyncStatus::Running => write!(f, "running"),
            SyncStatus::Success => write!(f, "success"),
            SyncStatus::PartialSuccess => write!(f, "partial_success"),
            SyncStatus::Failed => write!(f, "failed"),
            SyncStatus::Cancelled => write!(f, "cancelled"),
        }
    }
}

impl FromStr for SyncStatus {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "pending" => Ok(SyncStatus::Pending),
            "running" => Ok(SyncStatus::Running),
            "success" => Ok(SyncStatus::Success),
            "partial_success" => Ok(SyncStatus::PartialSuccess),
            "failed" => Ok(SyncStatus::Failed),
            "cancelled" => Ok(SyncStatus::Cancelled),
            _ => Err(format!("Unknown sync status: {}", s)),
        }
    }
}

/// 同步日志（存储在仓库内）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncLog {
    pub id: String,
    pub repository_id: i64,
    pub device_fingerprint: String,
    pub device_name: String,
    pub sync_type: SyncType,
    pub remote_name: String,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub total_files: i32,
    pub success_count: i32,
    pub fail_count: i32,
    pub skip_count: i32,
    pub conflict_count: i32,
    pub status: SyncStatus,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Fetch 结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchResult {
    pub repository_id: i64,
    pub remote_name: String,
    pub ahead: i32,
    pub behind: i32,
    pub fetched_objects: i32,
    pub fetched_size: i64,
    pub duration_ms: u64,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Push 结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushResult {
    pub repository_id: i64,
    pub remote_name: String,
    pub pushed_commits: i32,
    pub pushed_objects: i32,
    pub pushed_size: i64,
    pub duration_ms: u64,
    pub success: bool,
    pub rejected: bool,
    pub error_message: Option<String>,
}

/// Pull 结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullResult {
    pub repository_id: i64,
    pub remote_name: String,
    pub pulled_commits: i32,
    pub pulled_objects: i32,
    pub pulled_size: i64,
    pub fast_forwarded: bool,
    pub merged: bool,
    pub conflicts: i32,
    pub duration_ms: u64,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Sync 结果（组合 fetch + push 或 fetch + pull）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncResult {
    pub repository_id: i64,
    pub remote_name: String,
    pub fetch_result: FetchResult,
    pub push_result: Option<PushResult>,
    pub pull_result: Option<PullResult>,
    pub overall_success: bool,
    pub duration_ms: u64,
}

/// 同步进度事件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncProgressEvent {
    pub repository_id: i64,
    pub sync_id: String,
    pub sync_type: SyncType,
    pub phase: SyncPhase,
    pub current: i64,
    pub total: i64,
    pub current_file: Option<String>,
    pub speed: Option<f64>,  // bytes/sec
    pub elapsed_ms: u64,
    pub message: Option<String>,
}

/// 同步阶段
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncPhase {
    Initializing,
    FetchingState,
    FetchingObjects,
    PushingObjects,
    PushingState,
    Merging,
    Finalizing,
}

/// 同步冲突
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConflict {
    pub path: String,
    pub conflict_type: SyncConflictType,
    pub local_version: Option<String>,
    pub remote_version: Option<String>,
    pub base_version: Option<String>,
}

/// 同步冲突类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncConflictType {
    BothModified,
    LocalDeletedRemoteModified,
    RemoteDeletedLocalModified,
    BothDeleted,
    RenameConflict,
}

/// 同步配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    pub record_log: bool,
    pub force: bool,
    pub dry_run: bool,
    pub conflict_resolution: Option<ConflictResolution>,
    pub max_retries: i32,
    pub timeout_seconds: i32,
}

impl Default for SyncConfig {
    fn default() -> Self {
        Self {
            record_log: true,
            force: false,
            dry_run: false,
            conflict_resolution: None,
            max_retries: 3,
            timeout_seconds: 300,
        }
    }
}

/// 同步请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncRequest {
    pub repository_id: i64,
    pub remote_name: Option<String>,
    pub config: SyncConfig,
}

/// Ahead/Behind 计算
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AheadBehind {
    pub ahead: i32,
    pub behind: i32,
    pub ahead_commits: Vec<String>,
    pub behind_commits: Vec<String>,
}

/// 远端对象信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteObjectInfo {
    pub hash: String,
    pub size: i64,
    pub object_type: String,
    pub created_at: Option<DateTime<Utc>>,
}

/// 本地对象信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalObjectInfo {
    pub hash: String,
    pub path: String,
    pub size: i64,
}

/// 对象传输列表
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectTransferList {
    pub to_upload: Vec<LocalObjectInfo>,
    pub to_download: Vec<RemoteObjectInfo>,
    pub upload_size: i64,
    pub download_size: i64,
}

/// 仓库状态导出
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryStateExport {
    pub repository_id: String,
    pub device_fingerprint: String,
    pub device_name: String,
    pub export_time: DateTime<Utc>,
    pub head_commit_id: String,
    pub current_branch: String,
    pub branches: Vec<BranchStateExport>,
    pub remotes: Vec<RemoteStateExport>,
}

/// 分支状态导出
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchStateExport {
    pub name: String,
    pub head_commit_id: String,
    pub is_default: bool,
}

/// 远端状态导出
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteStateExport {
    pub remote_name: String,
    pub tracked_branch: String,
    pub last_fetch: Option<DateTime<Utc>>,
}
