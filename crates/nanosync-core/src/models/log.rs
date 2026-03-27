//! 应用日志相关数据模型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 日志级别
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Debug = 0,
    Info = 1,
    Warning = 2,
    Error = 3,
}

impl std::fmt::Display for LogLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LogLevel::Debug => write!(f, "DEBUG"),
            LogLevel::Info => write!(f, "INFO"),
            LogLevel::Warning => write!(f, "WARN"),
            LogLevel::Error => write!(f, "ERROR"),
        }
    }
}

impl std::str::FromStr for LogLevel {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "debug" => Ok(LogLevel::Debug),
            "info" => Ok(LogLevel::Info),
            "warning" | "warn" => Ok(LogLevel::Warning),
            "error" => Ok(LogLevel::Error),
            _ => Err(format!("Unknown log level: {}", s)),
        }
    }
}

/// 应用日志条目（存储在仓库内）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppLogEntry {
    pub id: String,
    pub repository_id: Option<i64>,
    pub device_fingerprint: String,
    pub device_name: String,
    pub username: String,
    pub level: LogLevel,
    pub category: String,
    pub message: String,
    pub details: Option<String>,
    pub source: Option<String>,
    pub context: Option<HashMap<String, String>>,
    pub stack_trace: Option<String>,
    pub timestamp: DateTime<Utc>,
}

/// 日志查询请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogQueryRequest {
    pub repository_id: Option<i64>,
    pub device_fingerprint: Option<String>,
    pub min_level: Option<LogLevel>,
    pub category: Option<String>,
    pub keyword: Option<String>,
    pub start_time: Option<DateTime<Utc>>,
    pub end_time: Option<DateTime<Utc>>,
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

impl Default for LogQueryRequest {
    fn default() -> Self {
        Self {
            repository_id: None,
            device_fingerprint: None,
            min_level: Some(LogLevel::Info),
            category: None,
            keyword: None,
            start_time: None,
            end_time: None,
            limit: Some(100),
            offset: Some(0),
        }
    }
}

/// 日志查询结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogQueryResult {
    pub entries: Vec<AppLogEntry>,
    pub total_count: i64,
    pub has_more: bool,
}

/// 日志统计
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogStatistics {
    pub total_count: i64,
    pub by_level: HashMap<String, i64>,
    pub by_category: HashMap<String, i64>,
    pub by_device: HashMap<String, i64>,
    pub oldest_timestamp: Option<DateTime<Utc>>,
    pub newest_timestamp: Option<DateTime<Utc>>,
}

/// 日志导出请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogExportRequest {
    pub repository_id: Option<i64>,
    pub device_fingerprint: Option<String>,
    pub min_level: Option<LogLevel>,
    pub start_time: Option<DateTime<Utc>>,
    pub end_time: Option<DateTime<Utc>>,
    pub format: LogExportFormat,
}

/// 日志导出格式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogExportFormat {
    Json,
    Csv,
    Text,
}

/// 日志导入结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogImportResult {
    pub imported_count: i32,
    pub skipped_count: i32,
    pub errors: Vec<String>,
}

/// 日志聚合
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogAggregation {
    pub key: String,
    pub count: i64,
    pub first_occurrence: DateTime<Utc>,
    pub last_occurrence: DateTime<Utc>,
    pub sample_message: String,
}

/// 设备日志摘要
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceLogSummary {
    pub device_fingerprint: String,
    pub device_name: String,
    pub log_count: i64,
    pub error_count: i64,
    pub warning_count: i64,
    pub last_activity: Option<DateTime<Utc>>,
    pub first_activity: Option<DateTime<Utc>>,
}
