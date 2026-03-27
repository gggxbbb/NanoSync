//! 版本控制相关数据模型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// 提交对象
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Commit {
    pub id: String,
    pub repository_id: i64,
    pub branch_name: String,
    pub parent_ids: Vec<String>,
    pub message: String,
    pub author: String,
    pub author_email: Option<String>,
    pub timestamp: DateTime<Utc>,
    pub tree_root: String,  // 树根哈希
    pub created_at: DateTime<Utc>,
}

/// 树条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TreeEntry {
    pub id: String,
    pub name: String,
    pub entry_type: TreeEntryType,
    pub object_id: String,
    pub mode: String,
}

/// 树条目类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TreeEntryType {
    File,
    Directory,
    Symlink,
}

/// 文件变更
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChange {
    pub id: String,
    pub repository_id: i64,
    pub commit_id: Option<String>,
    pub path: String,
    pub old_path: Option<String>,  // 重命名时
    pub change_type: ChangeType,
    pub old_hash: Option<String>,
    pub new_hash: Option<String>,
    pub old_size: Option<i64>,
    pub new_size: Option<i64>,
}

/// 变更类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ChangeType {
    Added,
    Modified,
    Deleted,
    Renamed,
    Copied,
    Conflict,
}

impl std::fmt::Display for ChangeType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ChangeType::Added => write!(f, "A"),
            ChangeType::Modified => write!(f, "M"),
            ChangeType::Deleted => write!(f, "D"),
            ChangeType::Renamed => write!(f, "R"),
            ChangeType::Copied => write!(f, "C"),
            ChangeType::Conflict => write!(f, "X"),
        }
    }
}

/// 分支
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Branch {
    pub id: String,
    pub repository_id: i64,
    pub name: String,
    pub head_commit_id: String,
    pub is_default: bool,
    pub created_at: DateTime<Utc>,
}

/// 暂存区条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StagingEntry {
    pub id: String,
    pub repository_id: i64,
    pub path: String,
    pub object_id: Option<String>,
    pub change_type: ChangeType,
    pub staged_at: DateTime<Utc>,
}

/// Stash
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stash {
    pub id: String,
    pub repository_id: i64,
    pub name: Option<String>,
    pub message: Option<String>,
    pub commit_id: String,
    pub branch_name: String,
    pub created_at: DateTime<Utc>,
}

/// Stash 条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StashEntry {
    pub id: String,
    pub stash_id: String,
    pub path: String,
    pub object_id: String,
    pub change_type: ChangeType,
}

/// 工作区状态
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WorkingDirectoryStatus {
    pub is_clean: bool,
    pub staged_changes: Vec<StagingEntry>,
    pub unstaged_changes: Vec<FileChange>,
    pub conflicts: Vec<FileChange>,
    pub current_branch: Option<String>,
    pub head_commit_id: Option<String>,
    pub ahead: i32,
    pub behind: i32,
}

/// Diff 结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffResult {
    pub path: String,
    pub hunks: Vec<DiffHunk>,
    pub is_binary: bool,
}

/// Diff Hunk
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffHunk {
    pub old_start: u32,
    pub old_lines: u32,
    pub new_start: u32,
    pub new_lines: u32,
    pub lines: Vec<DiffLine>,
}

/// Diff 行
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffLine {
    pub line_type: DiffLineType,
    pub content: String,
    pub old_line: Option<u32>,
    pub new_line: Option<u32>,
}

/// Diff 行类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DiffLineType {
    Context,
    Add,
    Delete,
}

/// 冲突信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conflict {
    pub path: String,
    pub conflict_type: ConflictType,
    pub ours_commit_id: Option<String>,
    pub theirs_commit_id: Option<String>,
    pub base_commit_id: Option<String>,
}

/// 冲突类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConflictType {
    Content,
    Rename,
    Delete,
    BothModified,
    OursDeleted,
    TheirsDeleted,
}

/// 提交请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommitRequest {
    pub repository_id: i64,
    pub message: String,
    pub author: Option<String>,
    pub author_email: Option<String>,
}

/// 添加请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddRequest {
    pub repository_id: i64,
    pub paths: Vec<String>,
}

/// 重置请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResetRequest {
    pub repository_id: i64,
    pub reset_type: ResetType,
    pub target: Option<String>,  // 提交ID或分支名
    pub paths: Option<Vec<String>>,
}

/// 重置类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ResetType {
    Soft,    // 保留暂存区和工作区
    Mixed,   // 重置暂存区，保留工作区
    Hard,    // 重置暂存区和工作区
}

/// 分支创建请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateBranchRequest {
    pub repository_id: i64,
    pub name: String,
    pub base_commit_id: Option<String>,
    pub checkout: bool,
}

/// 合并请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeRequest {
    pub repository_id: i64,
    pub source_branch: String,
    pub target_branch: Option<String>,  // 默认当前分支
    pub strategy: MergeStrategy,
}

/// 合并策略
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MergeStrategy {
    FastForward,
    Recursive,
    Ours,
    Theirs,
    Manual,
}

/// 合并结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeResult {
    pub success: bool,
    pub commit_id: Option<String>,
    pub conflicts: Vec<Conflict>,
    pub fast_forwarded: bool,
    pub message: Option<String>,
}

/// Stash 操作
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StashRequest {
    pub repository_id: i64,
    pub message: Option<String>,
    pub include_untracked: bool,
}

/// 对象索引条目（记录提交时的文件状态）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectIndexEntry {
    pub path: String,
    pub object_hash: String,
    pub file_size: i64,
    pub commit_id: String,
}

/// VC 同步记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcSyncRecord {
    pub id: String,
    pub repository_id: i64,
    pub remote_name: String,
    pub sync_type: VcSyncType,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub status: VcSyncStatus,
    pub error_message: Option<String>,
}

/// VC 同步类型（区别于主模块的 SyncType）
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VcSyncType {
    Fetch,
    Push,
    Pull,
    Sync,
}

/// VC 同步状态（区别于主模块的 SyncStatus）
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VcSyncStatus {
    Running,
    Success,
    Failed,
    Cancelled,
}
