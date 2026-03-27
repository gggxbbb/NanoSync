//! IPC 命令定义

use nanosync_core::models::*;
use serde::{Deserialize, Serialize};

/// 所有支持的命令
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Command {
    // ===== 系统命令 =====
    Ping(PingCommand),
    GetStatus,
    Shutdown,

    // ===== 仓库管理 =====
    ListRepositories,
    GetRepository(GetRepositoryCommand),
    RegisterRepository(RegisterRepositoryCommand),
    UnregisterRepository(UnregisterRepositoryCommand),
    ImportRepository(ImportRepositoryCommand),
    CloneRepository(CloneRepositoryCommand),
    MigrateRepository(MigrateRepositoryCommand),
    DeleteRepository(DeleteRepositoryCommand),

    // ===== 远程连接管理 =====
    ListRemoteConnections,
    GetRemoteConnection(GetRemoteConnectionCommand),
    CreateRemoteConnection(CreateRemoteConnectionCommand),
    UpdateRemoteConnection(UpdateRemoteConnectionCommand),
    DeleteRemoteConnection(DeleteRemoteConnectionCommand),
    TestRemoteConnection(TestRemoteConnectionCommand),

    // ===== 仓库远端绑定 =====
    ListRepositoryRemotes(ListRepositoryRemotesCommand),
    BindRemote(BindRemoteCommand),
    UnbindRemote(UnbindRemoteCommand),
    SetDefaultRemote(SetDefaultRemoteCommand),

    // ===== 同步操作 =====
    Fetch(FetchCommand),
    Push(PushCommand),
    Pull(PullCommand),
    Sync(SyncCommand),
    GetSyncStatus(GetSyncStatusCommand),

    // ===== 版本控制 =====
    VcStatus(VcStatusCommand),
    VcAdd(VcAddCommand),
    VcCommit(VcCommitCommand),
    VcLog(VcLogCommand),
    VcDiff(VcDiffCommand),
    VcReset(VcResetCommand),
    VcCreateBranch(VcCreateBranchCommand),
    VcSwitchBranch(VcSwitchBranchCommand),
    VcDeleteBranch(VcDeleteBranchCommand),
    VcStash(VcStashCommand),
    VcStashPop(VcStashPopCommand),
    VcStashList(VcStashListCommand),

    // ===== 自动化 =====
    ListAutomationRules(ListAutomationRulesCommand),
    GetAutomationRule(GetAutomationRuleCommand),
    CreateAutomationRule(CreateAutomationRuleCommand),
    UpdateAutomationRule(UpdateAutomationRuleCommand),
    DeleteAutomationRule(DeleteAutomationRuleCommand),
    ToggleAutomationRule(ToggleAutomationRuleCommand),
    TakeoverAutomationRule(TakeoverAutomationRuleCommand),
    GetAutomationRunnerStatus,

    // ===== 日志 =====
    QueryLogs(QueryLogsCommand),
    ClearLogs(ClearLogsCommand),
    ExportLogs(ExportLogsCommand),

    // ===== 设置 =====
    GetRepositorySettings(GetRepositorySettingsCommand),
    SaveRepositorySettings(SaveRepositorySettingsCommand),
}

// ===== 系统命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PingCommand {
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PongResponse {
    pub message: String,
    pub timestamp: String,
}

// ===== 仓库命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetRepositoryCommand {
    pub id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterRepositoryCommand {
    pub name: String,
    pub local_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnregisterRepositoryCommand {
    pub id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportRepositoryCommand {
    pub options: ImportRepositoryOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloneRepositoryCommand {
    pub options: CloneRepositoryOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MigrateRepositoryCommand {
    pub repository_id: i64,
    pub new_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteRepositoryCommand {
    pub repository_id: i64,
    pub delete_nanosync_folder: bool,
}

// ===== 远程连接命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetRemoteConnectionCommand {
    pub id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRemoteConnectionCommand {
    pub request: CreateRemoteConnectionRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateRemoteConnectionCommand {
    pub request: UpdateRemoteConnectionRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteRemoteConnectionCommand {
    pub id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestRemoteConnectionCommand {
    pub id: i64,
    pub test_path: Option<String>,
}

// ===== 仓库远端命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListRepositoryRemotesCommand {
    pub repository_id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BindRemoteCommand {
    pub request: BindRemoteRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnbindRemoteCommand {
    pub repository_id: i64,
    pub remote_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetDefaultRemoteCommand {
    pub repository_id: i64,
    pub remote_name: String,
}

// ===== 同步命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchCommand {
    pub repository_id: i64,
    pub remote_name: Option<String>,
    pub record_log: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushCommand {
    pub repository_id: i64,
    pub remote_name: Option<String>,
    pub force: bool,
    pub record_log: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullCommand {
    pub repository_id: i64,
    pub remote_name: Option<String>,
    pub record_log: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncCommand {
    pub repository_id: i64,
    pub remote_name: Option<String>,
    pub record_log: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetSyncStatusCommand {
    pub repository_id: i64,
}

// ===== 版本控制命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcStatusCommand {
    pub repository_id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcAddCommand {
    pub repository_id: i64,
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcCommitCommand {
    pub repository_id: i64,
    pub message: String,
    pub author: Option<String>,
    pub author_email: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcLogCommand {
    pub repository_id: i64,
    pub branch: Option<String>,
    pub limit: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcDiffCommand {
    pub repository_id: i64,
    pub path: Option<String>,
    pub staged: bool,
    pub commit_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcResetCommand {
    pub repository_id: i64,
    pub reset_type: ResetType,
    pub target: Option<String>,
    pub paths: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcCreateBranchCommand {
    pub repository_id: i64,
    pub name: String,
    pub base_commit_id: Option<String>,
    pub checkout: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcSwitchBranchCommand {
    pub repository_id: i64,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcDeleteBranchCommand {
    pub repository_id: i64,
    pub name: String,
    pub force: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcStashCommand {
    pub repository_id: i64,
    pub message: Option<String>,
    pub include_untracked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcStashPopCommand {
    pub repository_id: i64,
    pub stash_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcStashListCommand {
    pub repository_id: i64,
}

// ===== 自动化命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListAutomationRulesCommand {
    pub repository_id: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetAutomationRuleCommand {
    pub rule_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateAutomationRuleCommand {
    pub request: CreateAutomationRuleRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateAutomationRuleCommand {
    pub request: UpdateAutomationRuleRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteAutomationRuleCommand {
    pub rule_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToggleAutomationRuleCommand {
    pub rule_id: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TakeoverAutomationRuleCommand {
    pub rule_id: String,
    pub repository_id: i64,
}

// ===== 日志命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryLogsCommand {
    pub query: LogQueryRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClearLogsCommand {
    pub repository_id: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportLogsCommand {
    pub request: LogExportRequest,
}

// ===== 设置命令 =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GetRepositorySettingsCommand {
    pub repository_id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SaveRepositorySettingsCommand {
    pub repository_id: i64,
    pub settings: RepositoryLocalSettings,
}