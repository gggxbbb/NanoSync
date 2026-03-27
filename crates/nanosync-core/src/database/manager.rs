//! 软件级数据库管理器
//!
//! 只管理远程连接和已注册仓库两张表

use crate::database::schema;
use crate::error::{Error, Result};
use crate::models::*;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use std::path::Path;
use tracing::info;

/// 软件级数据库管理器
pub struct DatabaseManager {
    pool: SqlitePool,
}

impl DatabaseManager {
    /// 打开或创建数据库
    pub async fn open(db_path: &Path) -> Result<Self> {
        let db_url = format!("sqlite:{}?mode=rwc", db_path.to_string_lossy());
        
        info!("打开数据库: {}", db_path.display());
        
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect(&db_url)
            .await?;

        let manager = Self { pool };
        manager.initialize_schema().await?;
        
        Ok(manager)
    }

    /// 创建内存数据库（用于测试）
    pub async fn in_memory() -> Result<Self> {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await?;

        let manager = Self { pool };
        manager.initialize_schema().await?;
        
        Ok(manager)
    }

    /// 初始化 schema
    async fn initialize_schema(&self) -> Result<()> {
        sqlx::query(schema::APP_DB_SCHEMA)
            .execute(&self.pool)
            .await?;
        
        info!("数据库 schema 初始化完成");
        Ok(())
    }

    // ========== 已注册仓库 CRUD ==========

    /// 获取所有已注册仓库
    pub async fn list_repositories(&self) -> Result<Vec<RegisteredRepository>> {
        let repos = sqlx::query_as::<_, RegisteredRepository>(
            "SELECT * FROM registered_repositories ORDER BY last_accessed DESC NULLS LAST, added_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    /// 获取单个仓库
    pub async fn get_repository(&self, id: i64) -> Result<Option<RegisteredRepository>> {
        let repo = sqlx::query_as::<_, RegisteredRepository>(
            "SELECT * FROM registered_repositories WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(repo)
    }

    /// 通过路径获取仓库
    pub async fn get_repository_by_path(&self, path: &str) -> Result<Option<RegisteredRepository>> {
        let repo = sqlx::query_as::<_, RegisteredRepository>(
            "SELECT * FROM registered_repositories WHERE local_path = ?"
        )
        .bind(path)
        .fetch_optional(&self.pool)
        .await?;

        Ok(repo)
    }

    /// 注册仓库
    pub async fn register_repository(&self, name: &str, local_path: &str) -> Result<RegisteredRepository> {
        let now = chrono::Utc::now();
        
        let result = sqlx::query(
            "INSERT INTO registered_repositories (name, local_path, added_at) VALUES (?, ?, ?)"
        )
        .bind(name)
        .bind(local_path)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;

        let id = result.last_insert_rowid();
        
        Ok(RegisteredRepository {
            id,
            name: name.to_string(),
            local_path: local_path.to_string(),
            last_accessed: None,
            added_at: now,
        })
    }

    /// 更新仓库最后访问时间
    pub async fn update_repository_accessed(&self, id: i64) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();
        
        sqlx::query("UPDATE registered_repositories SET last_accessed = ? WHERE id = ?")
            .bind(&now)
            .bind(id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 更新仓库名称
    pub async fn update_repository_name(&self, id: i64, name: &str) -> Result<()> {
        sqlx::query("UPDATE registered_repositories SET name = ? WHERE id = ?")
            .bind(name)
            .bind(id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 更新仓库路径
    pub async fn update_repository_path(&self, id: i64, path: &str) -> Result<()> {
        sqlx::query("UPDATE registered_repositories SET local_path = ? WHERE id = ?")
            .bind(path)
            .bind(id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 注销仓库
    pub async fn unregister_repository(&self, id: i64) -> Result<()> {
        sqlx::query("DELETE FROM registered_repositories WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    // ========== 远程连接 CRUD ==========

    /// 获取所有远程连接
    pub async fn list_remote_connections(&self) -> Result<Vec<RemoteConnection>> {
        let connections = sqlx::query_as::<_, RemoteConnection>(
            "SELECT * FROM remote_connections ORDER BY created_at DESC"
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(connections)
    }

    /// 获取单个远程连接
    pub async fn get_remote_connection(&self, id: i64) -> Result<Option<RemoteConnection>> {
        let conn = sqlx::query_as::<_, RemoteConnection>(
            "SELECT * FROM remote_connections WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(conn)
    }

    /// 通过名称获取远程连接
    pub async fn get_remote_connection_by_name(&self, name: &str) -> Result<Option<RemoteConnection>> {
        let conn = sqlx::query_as::<_, RemoteConnection>(
            "SELECT * FROM remote_connections WHERE name = ?"
        )
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;

        Ok(conn)
    }

    /// 创建远程连接
    pub async fn create_remote_connection(&self, request: &CreateRemoteConnectionRequest) -> Result<RemoteConnection> {
        let now = chrono::Utc::now();
        let now_str = now.to_rfc3339();
        let protocol = request.protocol.to_string();

        // 检查名称是否已存在
        if self.get_remote_connection_by_name(&request.name).await?.is_some() {
            return Err(Error::RemoteConnectionNameExists(request.name.clone()));
        }

        let result = sqlx::query(
            "INSERT INTO remote_connections (name, protocol, host, port, username, password, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(&request.name)
        .bind(&protocol)
        .bind(&request.host)
        .bind(request.port)
        .bind(&request.username)
        .bind(&request.password)
        .bind(&now_str)
        .bind(&now_str)
        .execute(&self.pool)
        .await?;

        let id = result.last_insert_rowid();

        Ok(RemoteConnection {
            id,
            name: request.name.clone(),
            protocol,
            host: request.host.clone(),
            port: request.port,
            username: request.username.clone(),
            password: request.password.clone(),
            created_at: now,
            updated_at: now,
        })
    }

    /// 更新远程连接
    pub async fn update_remote_connection(&self, request: &UpdateRemoteConnectionRequest) -> Result<()> {
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "UPDATE remote_connections SET name = COALESCE(?, name), host = COALESCE(?, host), port = COALESCE(?, port), username = COALESCE(?, username), password = COALESCE(?, password), updated_at = ? WHERE id = ?"
        )
        .bind(&request.name)
        .bind(&request.host)
        .bind(request.port)
        .bind(&request.username)
        .bind(&request.password)
        .bind(&now)
        .bind(request.id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 删除远程连接
    pub async fn delete_remote_connection(&self, id: i64) -> Result<()> {
        sqlx::query("DELETE FROM remote_connections WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_database_manager() {
        let db = DatabaseManager::in_memory().await.unwrap();
        
        // 测试仓库注册
        let repo = db.register_repository("test", "/path/to/repo").await.unwrap();
        assert_eq!(repo.name, "test");
        
        let repos = db.list_repositories().await.unwrap();
        assert_eq!(repos.len(), 1);
        
        // 测试远程连接
        let conn_req = CreateRemoteConnectionRequest {
            name: "test-remote".to_string(),
            protocol: Protocol::Smb,
            host: "192.168.1.1".to_string(),
            port: Some(445),
            username: Some("user".to_string()),
            password: Some("pass".to_string()),
        };
        
        let conn = db.create_remote_connection(&conn_req).await.unwrap();
        assert_eq!(conn.name, "test-remote");
        
        let conns = db.list_remote_connections().await.unwrap();
        assert_eq!(conns.len(), 1);
    }
}