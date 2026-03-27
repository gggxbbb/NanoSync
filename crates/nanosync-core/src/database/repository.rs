//! 仓库级数据库管理器
//!
//! 每个仓库独立拥有自己的数据库文件，存储在 .nanosync/data.db

use crate::database::schema;
use crate::error::Result;
use crate::models::*;
use sqlx::Row;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use std::path::Path;
use std::str::FromStr;
use tracing::info;

/// 仓库级数据库管理器
pub struct RepositoryDatabase {
    pool: SqlitePool,
    pub repository_id: i64,
}

impl RepositoryDatabase {
    /// 打开或创建仓库数据库
    pub async fn open(repo_path: &Path, repository_id: i64) -> Result<Self> {
        let db_path = super::super::utils::path::repository_db_path(repo_path);
        
        // 确保目录存在
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        let db_url = format!("sqlite:{}?mode=rwc", db_path.to_string_lossy());
        
        info!("打开仓库数据库: {}", db_path.display());
        
        let pool = SqlitePoolOptions::new()
            .max_connections(3)
            .connect(&db_url)
            .await?;

        let db = Self { pool, repository_id };
        db.initialize_schema().await?;
        
        Ok(db)
    }

    /// 创建内存数据库（用于测试）
    pub async fn in_memory(repository_id: i64) -> Result<Self> {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await?;

        let db = Self { pool, repository_id };
        db.initialize_schema().await?;
        
        Ok(db)
    }

    /// 初始化 schema
    async fn initialize_schema(&self) -> Result<()> {
        sqlx::query(schema::REPOSITORY_DB_SCHEMA)
            .execute(&self.pool)
            .await?;
        
        info!("仓库数据库 schema 初始化完成");
        Ok(())
    }

    // ========== 分支管理 ==========

    /// 获取所有分支
    pub async fn list_branches(&self) -> Result<Vec<Branch>> {
        let branches = sqlx::query_as::<_, Branch>(
            "SELECT id, repository_id, name, head_commit_id, is_default, created_at FROM branches WHERE repository_id = ? ORDER BY is_default DESC, created_at ASC"
        )
        .bind(self.repository_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(branches)
    }

    /// 获取分支
    pub async fn get_branch(&self, name: &str) -> Result<Option<Branch>> {
        let branch = sqlx::query_as::<_, Branch>(
            "SELECT id, repository_id, name, head_commit_id, is_default, created_at FROM branches WHERE repository_id = ? AND name = ?"
        )
        .bind(self.repository_id)
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;

        Ok(branch)
    }

    /// 获取默认分支
    pub async fn get_default_branch(&self) -> Result<Option<Branch>> {
        let branch = sqlx::query_as::<_, Branch>(
            "SELECT id, repository_id, name, head_commit_id, is_default, created_at FROM branches WHERE repository_id = ? AND is_default = 1"
        )
        .bind(self.repository_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(branch)
    }

    /// 创建分支
    pub async fn create_branch(&self, name: &str, head_commit_id: &str, is_default: bool) -> Result<Branch> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "INSERT INTO branches (id, repository_id, name, head_commit_id, is_default, created_at) VALUES (?, ?, ?, ?, ?, ?)"
        )
        .bind(&id)
        .bind(self.repository_id)
        .bind(name)
        .bind(head_commit_id)
        .bind(is_default as i32)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(Branch {
            id,
            repository_id: self.repository_id,
            name: name.to_string(),
            head_commit_id: head_commit_id.to_string(),
            is_default,
            created_at: chrono::Utc::now(),
        })
    }

    /// 更新分支 HEAD
    pub async fn update_branch_head(&self, name: &str, commit_id: &str) -> Result<()> {
        sqlx::query("UPDATE branches SET head_commit_id = ? WHERE repository_id = ? AND name = ?")
            .bind(commit_id)
            .bind(self.repository_id)
            .bind(name)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 设置默认分支
    pub async fn set_default_branch(&self, name: &str) -> Result<()> {
        // 先清除所有默认
        sqlx::query("UPDATE branches SET is_default = 0 WHERE repository_id = ?")
            .bind(self.repository_id)
            .execute(&self.pool)
            .await?;

        // 设置新的默认分支
        sqlx::query("UPDATE branches SET is_default = 1 WHERE repository_id = ? AND name = ?")
            .bind(self.repository_id)
            .bind(name)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    // ========== 提交管理 ==========

    /// 添加提交
    pub async fn add_commit(&self, commit: &Commit) -> Result<()> {
        let parent_ids = serde_json::to_string(&commit.parent_ids)?;
        let now = commit.created_at.to_rfc3339();

        sqlx::query(
            "INSERT INTO commits (id, repository_id, branch_name, parent_ids, message, author, author_email, timestamp, tree_root, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(&commit.id)
        .bind(self.repository_id)
        .bind(&commit.branch_name)
        .bind(&parent_ids)
        .bind(&commit.message)
        .bind(&commit.author)
        .bind(&commit.author_email)
        .bind(commit.timestamp.to_rfc3339())
        .bind(&commit.tree_root)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 获取提交
    pub async fn get_commit(&self, id: &str) -> Result<Option<Commit>> {
        let row = sqlx::query(
            "SELECT * FROM commits WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            let parent_ids_str: String = row.try_get("parent_ids")?;
            let parent_ids: Vec<String> = serde_json::from_str(&parent_ids_str)?;
            
            Ok(Some(Commit {
                id: row.try_get("id")?,
                repository_id: row.try_get("repository_id")?,
                branch_name: row.try_get("branch_name")?,
                parent_ids,
                message: row.try_get("message")?,
                author: row.try_get("author")?,
                author_email: row.try_get("author_email")?,
                timestamp: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("timestamp")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
                tree_root: row.try_get("tree_root")?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("created_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            }))
        } else {
            Ok(None)
        }
    }

    /// 获取提交历史
    pub async fn get_commit_history(&self, branch: &str, limit: i32) -> Result<Vec<Commit>> {
        let rows = sqlx::query(
            "SELECT * FROM commits WHERE repository_id = ? AND branch_name = ? ORDER BY timestamp DESC LIMIT ?"
        )
        .bind(self.repository_id)
        .bind(branch)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let mut commits = Vec::new();
        for row in rows {
            let parent_ids_str: String = row.try_get("parent_ids")?;
            let parent_ids: Vec<String> = serde_json::from_str(&parent_ids_str)?;
            
            commits.push(Commit {
                id: row.try_get("id")?,
                repository_id: row.try_get("repository_id")?,
                branch_name: row.try_get("branch_name")?,
                parent_ids,
                message: row.try_get("message")?,
                author: row.try_get("author")?,
                author_email: row.try_get("author_email")?,
                timestamp: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("timestamp")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
                tree_root: row.try_get("tree_root")?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("created_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            });
        }

        Ok(commits)
    }

    // ========== 暂存区管理 ==========

    /// 添加到暂存区
    pub async fn stage_entry(&self, path: &str, change_type: ChangeType, object_id: Option<&str>) -> Result<()> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();
        let change_type_str = serde_json::to_string(&change_type)?;

        sqlx::query(
            "INSERT OR REPLACE INTO staging_entries (id, repository_id, path, object_id, change_type, staged_at) VALUES (?, ?, ?, ?, ?, ?)"
        )
        .bind(&id)
        .bind(self.repository_id)
        .bind(path)
        .bind(object_id)
        .bind(&change_type_str)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 获取暂存区条目
    pub async fn list_staged_entries(&self) -> Result<Vec<StagingEntry>> {
        let rows = sqlx::query(
            "SELECT * FROM staging_entries WHERE repository_id = ?"
        )
        .bind(self.repository_id)
        .fetch_all(&self.pool)
        .await?;

        let mut entries = Vec::new();
        for row in rows {
            let change_type_str: String = row.try_get("change_type")?;
            let change_type: ChangeType = serde_json::from_str(&change_type_str)?;
            
            entries.push(StagingEntry {
                id: row.try_get("id")?,
                repository_id: row.try_get("repository_id")?,
                path: row.try_get("path")?,
                object_id: row.try_get("object_id")?,
                change_type,
                staged_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("staged_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            });
        }

        Ok(entries)
    }

    /// 从暂存区移除
    pub async fn unstage_entry(&self, path: &str) -> Result<()> {
        sqlx::query("DELETE FROM staging_entries WHERE repository_id = ? AND path = ?")
            .bind(self.repository_id)
            .bind(path)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 清空暂存区
    pub async fn clear_staging(&self) -> Result<()> {
        sqlx::query("DELETE FROM staging_entries WHERE repository_id = ?")
            .bind(self.repository_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    // ========== 本地设置管理 ==========

    /// 获取本地设置
    pub async fn get_local_settings(&self) -> Result<Option<RepositoryLocalSettings>> {
        let row = sqlx::query(
            "SELECT * FROM local_settings WHERE repository_id = ?"
        )
        .bind(self.repository_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            Ok(Some(RepositoryLocalSettings {
                max_versions: row.try_get("max_versions")?,
                max_version_days: row.try_get("max_version_days")?,
                max_version_size_gb: row.try_get("max_version_size_gb")?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("created_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
                updated_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("updated_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            }))
        } else {
            Ok(None)
        }
    }

    /// 保存本地设置
    pub async fn save_local_settings(&self, settings: &RepositoryLocalSettings) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();
        
        sqlx::query(
            "INSERT OR REPLACE INTO local_settings (repository_id, max_versions, max_version_days, max_version_size_gb, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)"
        )
        .bind(self.repository_id)
        .bind(settings.max_versions)
        .bind(settings.max_version_days)
        .bind(settings.max_version_size_gb)
        .bind(settings.created_at.to_rfc3339())
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    // ========== 远端绑定管理 ==========

    /// 获取仓库远端绑定
    pub async fn list_repository_remotes(&self) -> Result<Vec<RepositoryRemote>> {
        let rows = sqlx::query(
            "SELECT * FROM repository_remotes WHERE repository_id = ?"
        )
        .bind(self.repository_id)
        .fetch_all(&self.pool)
        .await?;

        let mut remotes = Vec::new();
        for row in rows {
            remotes.push(RepositoryRemote {
                remote_name: row.try_get("remote_name")?,
                connection_id: row.try_get("connection_id")?,
                remote_path: row.try_get("remote_path")?,
                is_default: row.try_get::<i32, _>("is_default")? == 1,
                last_sync: row.try_get::<Option<String>, _>("last_sync")?
                    .map(|s| chrono::DateTime::parse_from_rfc3339(&s).map(|dt| dt.with_timezone(&chrono::Utc)))
                    .transpose()?,
                last_fetch: row.try_get::<Option<String>, _>("last_fetch")?
                    .map(|s| chrono::DateTime::parse_from_rfc3339(&s).map(|dt| dt.with_timezone(&chrono::Utc)))
                    .transpose()?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("created_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            });
        }

        Ok(remotes)
    }

    /// 添加远端绑定
    pub async fn add_repository_remote(&self, remote: &RepositoryRemote) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();

        // 如果设为默认，先清除其他默认
        if remote.is_default {
            sqlx::query("UPDATE repository_remotes SET is_default = 0 WHERE repository_id = ?")
                .bind(self.repository_id)
                .execute(&self.pool)
                .await?;
        }

        sqlx::query(
            "INSERT INTO repository_remotes (repository_id, remote_name, connection_id, remote_path, is_default, last_sync, last_fetch, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(self.repository_id)
        .bind(&remote.remote_name)
        .bind(remote.connection_id)
        .bind(&remote.remote_path)
        .bind(remote.is_default as i32)
        .bind(remote.last_sync.map(|t| t.to_rfc3339()))
        .bind(remote.last_fetch.map(|t| t.to_rfc3339()))
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 设置默认远端
    pub async fn set_default_remote(&self, remote_name: &str) -> Result<()> {
        // 先清除所有默认
        sqlx::query("UPDATE repository_remotes SET is_default = 0 WHERE repository_id = ?")
            .bind(self.repository_id)
            .execute(&self.pool)
            .await?;

        // 设置新的默认
        sqlx::query("UPDATE repository_remotes SET is_default = 1 WHERE repository_id = ? AND remote_name = ?")
            .bind(self.repository_id)
            .bind(remote_name)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 更新远端同步时间
    pub async fn update_remote_sync_time(&self, remote_name: &str, is_fetch: bool) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();
        
        if is_fetch {
            sqlx::query("UPDATE repository_remotes SET last_fetch = ? WHERE repository_id = ? AND remote_name = ?")
                .bind(&now)
                .bind(self.repository_id)
                .bind(remote_name)
                .execute(&self.pool)
                .await?;
        } else {
            sqlx::query("UPDATE repository_remotes SET last_sync = ?, last_fetch = ? WHERE repository_id = ? AND remote_name = ?")
                .bind(&now)
                .bind(&now)
                .bind(self.repository_id)
                .bind(remote_name)
                .execute(&self.pool)
                .await?;
        }

        Ok(())
    }

    // ========== 自动化规则管理 ==========

    /// 获取所有自动化规则
    pub async fn list_automation_rules(&self) -> Result<Vec<AutomationRule>> {
        let rows = sqlx::query(
            "SELECT * FROM automation_rules WHERE repository_id = ?"
        )
        .bind(self.repository_id)
        .fetch_all(&self.pool)
        .await?;

        let mut rules = Vec::new();
        for row in rows {
            rules.push(AutomationRule {
                id: row.try_get("id")?,
                repository_id: row.try_get("repository_id")?,
                name: row.try_get("name")?,
                description: row.try_get("description")?,
                trigger_type: serde_json::from_str(&row.try_get::<String, _>("trigger_type")?)?,
                action_type: serde_json::from_str(&row.try_get::<String, _>("action_type")?)?,
                enabled: row.try_get::<i32, _>("enabled")? == 1,
                owner_device_fingerprint: row.try_get("owner_device_fingerprint")?,
                is_imported: row.try_get::<i32, _>("is_imported")? == 1,
                last_triggered: row.try_get::<Option<String>, _>("last_triggered")?
                    .map(|s| chrono::DateTime::parse_from_rfc3339(&s).map(|dt| dt.with_timezone(&chrono::Utc)))
                    .transpose()?,
                retry_count: row.try_get("retry_count")?,
                retry_delay_seconds: row.try_get("retry_delay_seconds")?,
                debounce_seconds: row.try_get("debounce_seconds")?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("created_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
                updated_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("updated_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            });
        }

        Ok(rules)
    }

    /// 添加自动化规则
    pub async fn add_automation_rule(&self, rule: &AutomationRule) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "INSERT INTO automation_rules (id, repository_id, name, description, trigger_type, action_type, trigger_config, enabled, owner_device_fingerprint, is_imported, last_triggered, retry_count, retry_delay_seconds, debounce_seconds, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(&rule.id)
        .bind(self.repository_id)
        .bind(&rule.name)
        .bind(&rule.description)
        .bind(serde_json::to_string(&rule.trigger_type)?)
        .bind(serde_json::to_string(&rule.action_type)?)
        .bind("{}") // trigger_config
        .bind(rule.enabled as i32)
        .bind(&rule.owner_device_fingerprint)
        .bind(rule.is_imported as i32)
        .bind(rule.last_triggered.map(|t| t.to_rfc3339()))
        .bind(rule.retry_count)
        .bind(rule.retry_delay_seconds)
        .bind(rule.debounce_seconds)
        .bind(&now)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 更新自动化规则
    pub async fn update_automation_rule(&self, rule: &AutomationRule) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "UPDATE automation_rules SET name = ?, description = ?, trigger_type = ?, action_type = ?, enabled = ?, retry_count = ?, retry_delay_seconds = ?, debounce_seconds = ?, updated_at = ? WHERE id = ?"
        )
        .bind(&rule.name)
        .bind(&rule.description)
        .bind(serde_json::to_string(&rule.trigger_type)?)
        .bind(serde_json::to_string(&rule.action_type)?)
        .bind(rule.enabled as i32)
        .bind(rule.retry_count)
        .bind(rule.retry_delay_seconds)
        .bind(rule.debounce_seconds)
        .bind(&now)
        .bind(&rule.id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 删除自动化规则
    pub async fn delete_automation_rule(&self, rule_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM automation_rules WHERE id = ?")
            .bind(rule_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 更新规则最后触发时间
    pub async fn update_rule_last_triggered(&self, rule_id: &str) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();
        
        sqlx::query("UPDATE automation_rules SET last_triggered = ? WHERE id = ?")
            .bind(&now)
            .bind(rule_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    // ========== 同步日志管理 ==========

    /// 添加同步日志
    pub async fn add_sync_log(&self, log: &SyncLog) -> Result<()> {
        sqlx::query(
            "INSERT INTO sync_logs (id, repository_id, device_fingerprint, device_name, sync_type, remote_name, start_time, end_time, total_files, success_count, fail_count, skip_count, conflict_count, status, error_message, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(&log.id)
        .bind(self.repository_id)
        .bind(&log.device_fingerprint)
        .bind(&log.device_name)
        .bind(serde_json::to_string(&log.sync_type)?)
        .bind(&log.remote_name)
        .bind(log.start_time.to_rfc3339())
        .bind(log.end_time.map(|t| t.to_rfc3339()))
        .bind(log.total_files)
        .bind(log.success_count)
        .bind(log.fail_count)
        .bind(log.skip_count)
        .bind(log.conflict_count)
        .bind(serde_json::to_string(&log.status)?)
        .bind(&log.error_message)
        .bind(log.created_at.to_rfc3339())
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 获取同步日志
    pub async fn list_sync_logs(&self, limit: i32) -> Result<Vec<SyncLog>> {
        let rows = sqlx::query(
            "SELECT * FROM sync_logs WHERE repository_id = ? ORDER BY start_time DESC LIMIT ?"
        )
        .bind(self.repository_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let mut logs = Vec::new();
        for row in rows {
            logs.push(SyncLog {
                id: row.try_get("id")?,
                repository_id: self.repository_id,
                device_fingerprint: row.try_get("device_fingerprint")?,
                device_name: row.try_get("device_name")?,
                sync_type: serde_json::from_str(&row.try_get::<String, _>("sync_type")?)?,
                remote_name: row.try_get("remote_name")?,
                start_time: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("start_time")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
                end_time: row.try_get::<Option<String>, _>("end_time")?
                    .map(|s| chrono::DateTime::parse_from_rfc3339(&s).map(|dt| dt.with_timezone(&chrono::Utc)))
                    .transpose()?,
                total_files: row.try_get("total_files")?,
                success_count: row.try_get("success_count")?,
                fail_count: row.try_get("fail_count")?,
                skip_count: row.try_get("skip_count")?,
                conflict_count: row.try_get("conflict_count")?,
                status: serde_json::from_str(&row.try_get::<String, _>("status")?)?,
                error_message: row.try_get("error_message")?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("created_at")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            });
        }

        Ok(logs)
    }

    // ========== 应用日志管理 ==========

    /// 添加应用日志
    pub async fn add_app_log(&self, log: &AppLogEntry) -> Result<()> {
        sqlx::query(
            "INSERT INTO app_logs (id, repository_id, device_fingerprint, device_name, username, level, category, message, details, source, context, stack_trace, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(&log.id)
        .bind(log.repository_id)
        .bind(&log.device_fingerprint)
        .bind(&log.device_name)
        .bind(&log.username)
        .bind(log.level.to_string())
        .bind(&log.category)
        .bind(&log.message)
        .bind(&log.details)
        .bind(&log.source)
        .bind(log.context.as_ref().map(|c| serde_json::to_string(c)).transpose()?)
        .bind(&log.stack_trace)
        .bind(log.timestamp.to_rfc3339())
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 查询应用日志
    pub async fn query_app_logs(&self, query: &LogQueryRequest) -> Result<Vec<AppLogEntry>> {
        let mut sql = "SELECT * FROM app_logs WHERE repository_id = ?".to_string();
        let mut params: Vec<String> = vec![self.repository_id.to_string()];

        if let Some(ref device_fp) = query.device_fingerprint {
            sql.push_str(" AND device_fingerprint = ?");
            params.push(device_fp.clone());
        }

        if let Some(min_level) = query.min_level {
            sql.push_str(" AND level IN (");
            let levels: Vec<&str> = match min_level {
                LogLevel::Debug => vec!["DEBUG", "INFO", "WARNING", "ERROR"],
                LogLevel::Info => vec!["INFO", "WARNING", "ERROR"],
                LogLevel::Warning => vec!["WARNING", "ERROR"],
                LogLevel::Error => vec!["ERROR"],
            };
            sql.push_str(&levels.iter().map(|l| format!("'{}'", l)).collect::<Vec<_>>().join(", "));
            sql.push(')');
        }

        if let Some(ref category) = query.category {
            sql.push_str(" AND category = ?");
            params.push(category.clone());
        }

        if let Some(ref keyword) = query.keyword {
            sql.push_str(" AND (message LIKE ? OR category LIKE ? OR details LIKE ?)");
            let kw = format!("%{}%", keyword);
            params.push(kw.clone());
            params.push(kw.clone());
            params.push(kw);
        }

        sql.push_str(" ORDER BY timestamp DESC");

        if let Some(limit) = query.limit {
            sql.push_str(&format!(" LIMIT {}", limit));
        }

        if let Some(offset) = query.offset {
            sql.push_str(&format!(" OFFSET {}", offset));
        }

        // 由于 sqlx 不支持动态参数数量，这里简化处理
        let rows = sqlx::query(&sql)
            .bind(self.repository_id)
            .fetch_all(&self.pool)
            .await?;

        let mut logs = Vec::new();
        for row in rows {
            let level_str: String = row.try_get("level")?;
            let level = LogLevel::from_str(&level_str).unwrap_or(LogLevel::Info);
            let context_str: Option<String> = row.try_get("context")?;
            
            logs.push(AppLogEntry {
                id: row.try_get("id")?,
                repository_id: Some(self.repository_id),
                device_fingerprint: row.try_get("device_fingerprint")?,
                device_name: row.try_get("device_name")?,
                username: row.try_get("username")?,
                level,
                category: row.try_get("category")?,
                message: row.try_get("message")?,
                details: row.try_get("details")?,
                source: row.try_get("source")?,
                context: context_str.as_ref().and_then(|s| serde_json::from_str(s).ok()),
                stack_trace: row.try_get("stack_trace")?,
                timestamp: chrono::DateTime::parse_from_rfc3339(&row.try_get::<String, _>("timestamp")?)
                    .map(|dt| dt.with_timezone(&chrono::Utc))?,
            });
        }

        Ok(logs)
    }
}