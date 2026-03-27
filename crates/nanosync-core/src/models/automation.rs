//! 自动化规则相关数据模型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// 自动化规则（存储在仓库内）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationRule {
    pub id: String,
    pub repository_id: i64,
    pub name: String,
    pub description: Option<String>,
    pub trigger_type: TriggerType,
    pub action_type: ActionType,
    pub enabled: bool,
    pub owner_device_fingerprint: String,
    pub is_imported: bool,  // 是否从其他设备导入
    pub last_triggered: Option<DateTime<Utc>>,
    pub retry_count: i32,
    pub retry_delay_seconds: i32,
    pub debounce_seconds: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// 触发类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TriggerType {
    TimeBased,      // 定时触发
    ChangeBased,    // 变更触发
    Schedule,       // 计划触发（cron）
}

/// 动作类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ActionType {
    Sync,
    Commit,
    Push,
    Pull,
    SyncAndPush,
    CommitAndPush,
    Fetch,
}

/// 定时触发配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeBasedTrigger {
    pub interval_minutes: i32,
}

/// 变更触发配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChangeBasedTrigger {
    pub debounce_seconds: i32,
    pub include_untracked: bool,
}

/// 创建自动化规则请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateAutomationRuleRequest {
    pub repository_id: i64,
    pub name: String,
    pub description: Option<String>,
    pub trigger_type: TriggerType,
    pub action_type: ActionType,
    pub trigger_config: TriggerConfig,
    pub retry_count: Option<i32>,
    pub retry_delay_seconds: Option<i32>,
    pub debounce_seconds: Option<i32>,
}

/// 触发配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerConfig {
    pub interval_minutes: Option<i32>,
    pub debounce_seconds: Option<i32>,
    pub include_untracked: Option<bool>,
    pub cron_expression: Option<String>,
}

/// 更新自动化规则请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateAutomationRuleRequest {
    pub rule_id: String,
    pub name: Option<String>,
    pub description: Option<String>,
    pub trigger_type: Option<TriggerType>,
    pub action_type: Option<ActionType>,
    pub trigger_config: Option<TriggerConfig>,
    pub enabled: Option<bool>,
    pub retry_count: Option<i32>,
    pub retry_delay_seconds: Option<i32>,
    pub debounce_seconds: Option<i32>,
}

/// 自动化执行记录（存储在仓库内）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationExecution {
    pub id: String,
    pub rule_id: String,
    pub repository_id: i64,
    pub device_fingerprint: String,
    pub device_name: String,
    pub trigger_type: TriggerType,
    pub action_type: ActionType,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub status: ExecutionStatus,
    pub error_message: Option<String>,
    pub retry_attempt: i32,
}

/// 执行状态
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExecutionStatus {
    Running,
    Success,
    Failed,
    Cancelled,
    RetryPending,
}

/// 规则接管请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TakeoverRuleRequest {
    pub rule_id: String,
    pub repository_id: i64,
}

/// 规则导入结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleImportResult {
    pub rule_id: String,
    pub name: String,
    pub original_device_fingerprint: String,
    pub original_device_name: Option<String>,
    pub needs_takeover: bool,
}

/// 自动化运行器状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationRunnerStatus {
    pub is_running: bool,
    pub active_rules_count: i32,
    pub last_tick: Option<DateTime<Utc>>,
    pub pending_executions: i32,
    pub current_executions: i32,
}

/// 自动化规则摘要
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationRuleSummary {
    pub id: String,
    pub repository_id: i64,
    pub repository_name: String,
    pub name: String,
    pub trigger_type: TriggerType,
    pub action_type: ActionType,
    pub enabled: bool,
    pub is_imported: bool,
    pub needs_takeover: bool,
    pub last_triggered: Option<DateTime<Utc>>,
}
