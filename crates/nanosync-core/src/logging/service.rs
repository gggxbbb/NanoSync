//! 日志服务实现

use crate::database::RepositoryDatabase;
use crate::device::DeviceIdentity;
use crate::error::Result;
use crate::models::*;
use tracing::info;

/// 日志服务
pub struct LogService {
    device_identity: DeviceIdentity,
}

impl LogService {
    pub fn new(device_identity: DeviceIdentity) -> Self {
        Self { device_identity }
    }

    /// 记录日志
    pub async fn log(
        &self,
        repo_db: Option<&RepositoryDatabase>,
        level: LogLevel,
        category: &str,
        message: &str,
        details: Option<&str>,
        source: Option<&str>,
        context: Option<std::collections::HashMap<String, String>>,
        stack_trace: Option<&str>,
    ) -> Result<String> {
        let id = crate::utils::hash::generate_uuid();
        let repository_id = repo_db.as_ref().map(|db| db.repository_id);
        let entry = AppLogEntry {
            id: id.clone(),
            repository_id,
            device_fingerprint: self.device_identity.fingerprint.clone(),
            device_name: self.device_identity.display_name(),
            username: self.device_identity.username.clone(),
            level,
            category: category.to_string(),
            message: message.to_string(),
            details: details.map(|s| s.to_string()),
            source: source.map(|s| s.to_string()),
            context,
            stack_trace: stack_trace.map(|s| s.to_string()),
            timestamp: chrono::Utc::now(),
        };

        if let Some(db) = repo_db {
            db.add_app_log(&entry).await?;
        }

        Ok(id)
    }

    /// 查询日志
    pub async fn query_logs(
        &self,
        repo_db: Option<&RepositoryDatabase>,
        query: &LogQueryRequest,
    ) -> Result<LogQueryResult> {
        if let Some(db) = repo_db {
            let entries = db.query_app_logs(query).await?;
            
            Ok(LogQueryResult {
                total_count: entries.len() as i64,
                has_more: false,
                entries,
            })
        } else {
            Ok(LogQueryResult {
                total_count: 0,
                has_more: false,
                entries: vec![],
            })
        }
    }

    /// 清空日志
    pub async fn clear_logs(&self, _repo_db: Option<&RepositoryDatabase>) -> Result<i32> {
        // TODO: 实现日志清空
        info!("日志已清空");
        Ok(0)
    }

    /// 导出日志
    pub async fn export_logs(
        &self,
        repo_db: Option<&RepositoryDatabase>,
        request: &LogExportRequest,
    ) -> Result<Vec<u8>> {
        let query = LogQueryRequest {
            repository_id: request.repository_id,
            device_fingerprint: request.device_fingerprint.clone(),
            min_level: request.min_level,
            category: None,
            keyword: None,
            start_time: request.start_time,
            end_time: request.end_time,
            limit: None,
            offset: None,
        };

        let result = self.query_logs(repo_db, &query).await?;

        match request.format {
            LogExportFormat::Json => {
                let json = serde_json::to_string_pretty(&result.entries)?;
                Ok(json.into_bytes())
            }
            LogExportFormat::Csv => {
                let mut csv = String::from("timestamp,level,category,message,details\n");
                for entry in result.entries {
                    csv.push_str(&format!(
                        "{},{},{},{},{}\n",
                        entry.timestamp.to_rfc3339(),
                        entry.level,
                        entry.category,
                        entry.message.replace(',', "\\,"),
                        entry.details.unwrap_or_default().replace(',', "\\,"),
                    ));
                }
                Ok(csv.into_bytes())
            }
            LogExportFormat::Text => {
                let mut text = String::new();
                for entry in result.entries {
                    text.push_str(&format!(
                        "[{}] [{}] [{}] {}\n",
                        entry.timestamp.to_rfc3339(),
                        entry.level,
                        entry.category,
                        entry.message,
                    ));
                    if let Some(details) = &entry.details {
                        text.push_str(&format!("  Details: {}\n", details));
                    }
                }
                Ok(text.into_bytes())
            }
        }
    }

    /// 获取日志统计
    pub async fn get_statistics(
        &self,
        _repo_db: Option<&RepositoryDatabase>,
    ) -> Result<LogStatistics> {
        // TODO: 实现日志统计
        Ok(LogStatistics {
            total_count: 0,
            by_level: std::collections::HashMap::new(),
            by_category: std::collections::HashMap::new(),
            by_device: std::collections::HashMap::new(),
            oldest_timestamp: None,
            newest_timestamp: None,
        })
    }

    /// Debug 日志
    pub async fn debug(&self, repo_db: Option<&RepositoryDatabase>, category: &str, message: &str) -> Result<String> {
        self.log(repo_db, LogLevel::Debug, category, message, None, None, None, None).await
    }

    /// Info 日志
    pub async fn info(&self, repo_db: Option<&RepositoryDatabase>, category: &str, message: &str) -> Result<String> {
        self.log(repo_db, LogLevel::Info, category, message, None, None, None, None).await
    }

    /// Warning 日志
    pub async fn warning(&self, repo_db: Option<&RepositoryDatabase>, category: &str, message: &str) -> Result<String> {
        self.log(repo_db, LogLevel::Warning, category, message, None, None, None, None).await
    }

    /// Error 日志
    pub async fn error(&self, repo_db: Option<&RepositoryDatabase>, category: &str, message: &str, error: Option<&str>) -> Result<String> {
        self.log(repo_db, LogLevel::Error, category, message, error, None, None, None).await
    }
}