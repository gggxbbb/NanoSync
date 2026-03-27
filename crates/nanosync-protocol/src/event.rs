//! IPC 事件定义

use nanosync_core::models::{
    SyncProgressEvent, TriggerType, ActionType,
};
use nanosync_core::models::sync::SyncType;
use serde::{Deserialize, Serialize};

/// 事件类型
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    // ===== 同步事件 =====
    SyncProgress(SyncProgressEvent),
    SyncStarted(SyncStartedEvent),
    SyncCompleted(SyncCompletedEvent),
    SyncFailed(SyncFailedEvent),

    // ===== 自动化事件 =====
    AutomationTriggered(AutomationTriggeredEvent),
    AutomationCompleted(AutomationCompletedEvent),
    AutomationFailed(AutomationFailedEvent),

    // ===== 仓库事件 =====
    RepositoryAdded(RepositoryChangedEvent),
    RepositoryRemoved(RepositoryChangedEvent),
    RepositoryUpdated(RepositoryChangedEvent),

    // ===== 远程连接事件 =====
    RemoteConnectionAdded(RemoteConnectionChangedEvent),
    RemoteConnectionRemoved(RemoteConnectionChangedEvent),
    RemoteConnectionUpdated(RemoteConnectionChangedEvent),

    // ===== 版本控制事件 =====
    CommitCreated(CommitCreatedEvent),
    BranchCreated(BranchChangedEvent),
    BranchSwitched(BranchChangedEvent),
    WorkingDirectoryChanged(WorkingDirectoryChangedEvent),

    // ===== 系统事件 =====
    ServiceStarted,
    ServiceStopping,
    Error(ErrorEvent),
}

// ===== 同步事件 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncStartedEvent {
    pub sync_id: String,
    pub repository_id: i64,
    pub repository_name: String,
    pub sync_type: SyncType,
    pub remote_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncCompletedEvent {
    pub sync_id: String,
    pub repository_id: i64,
    pub sync_type: SyncType,
    pub remote_name: String,
    pub duration_ms: u64,
    pub result: SyncResultSummary,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncFailedEvent {
    pub sync_id: String,
    pub repository_id: i64,
    pub sync_type: SyncType,
    pub remote_name: String,
    pub error: String,
}

/// 同步结果摘要
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncResultSummary {
    pub files_processed: i32,
    pub files_uploaded: i32,
    pub files_downloaded: i32,
    pub conflicts: i32,
    pub bytes_transferred: i64,
}

// ===== 自动化事件 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationTriggeredEvent {
    pub execution_id: String,
    pub rule_id: String,
    pub rule_name: String,
    pub repository_id: i64,
    pub trigger_type: TriggerType,
    pub action_type: ActionType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationCompletedEvent {
    pub execution_id: String,
    pub rule_id: String,
    pub repository_id: i64,
    pub success: bool,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationFailedEvent {
    pub execution_id: String,
    pub rule_id: String,
    pub repository_id: i64,
    pub error: String,
    pub retry_count: i32,
    pub will_retry: bool,
}

// ===== 仓库事件 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryChangedEvent {
    pub repository_id: i64,
    pub repository_name: String,
    pub local_path: String,
}

// ===== 远程连接事件 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteConnectionChangedEvent {
    pub connection_id: i64,
    pub connection_name: String,
    pub protocol: String,
}

// ===== 版本控制事件 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitCreatedEvent {
    pub repository_id: i64,
    pub commit_id: String,
    pub message: String,
    pub author: String,
    pub branch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchChangedEvent {
    pub repository_id: i64,
    pub branch_name: String,
    pub commit_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkingDirectoryChangedEvent {
    pub repository_id: i64,
    pub is_dirty: bool,
    pub staged_count: i32,
    pub unstaged_count: i32,
}

// ===== 系统事件 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorEvent {
    pub code: String,
    pub message: String,
    pub details: Option<String>,
}

/// 事件订阅请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubscribeRequest {
    pub event_types: Vec<String>,  // 空表示订阅所有事件
}

/// 取消订阅请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsubscribeRequest {
    pub event_types: Vec<String>,
}