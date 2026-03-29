//! 远程连接管理器

use crate::database::DatabaseManager;
use crate::database::RepositoryDatabase;
use crate::error::{Error, Result};
use crate::models::*;
use crate::remote::smb::SmbClient;
use crate::remote::unc::UncClient;
use crate::remote::webdav::WebDavClient;
use std::sync::Arc;
use std::time::Instant;

/// 远程连接管理器
pub struct RemoteConnectionManager {
    db: Arc<DatabaseManager>,
}

impl RemoteConnectionManager {
    pub fn new(db: Arc<DatabaseManager>) -> Self {
        Self { db }
    }

    /// 列出所有远程连接
    pub async fn list_connections(&self) -> Result<Vec<RemoteConnection>> {
        self.db.list_remote_connections().await
    }

    /// 获取单个远程连接
    pub async fn get_connection(&self, id: i64) -> Result<Option<RemoteConnection>> {
        self.db.get_remote_connection(id).await
    }

    /// 通过名称获取远程连接
    pub async fn get_connection_by_name(&self, name: &str) -> Result<Option<RemoteConnection>> {
        self.db.get_remote_connection_by_name(name).await
    }

    /// 创建远程连接
    pub async fn create_connection(&self, request: &CreateRemoteConnectionRequest) -> Result<RemoteConnection> {
        self.db.create_remote_connection(request).await
    }

    /// 更新远程连接
    pub async fn update_connection(&self, request: &UpdateRemoteConnectionRequest) -> Result<()> {
        self.db.update_remote_connection(request).await
    }

    /// 删除远程连接
    pub async fn delete_connection(&self, id: i64) -> Result<()> {
        let repositories = self.db.list_repositories().await?;
        for repo in repositories {
            let repo_db = RepositoryDatabase::open(std::path::Path::new(&repo.local_path), repo.id).await?;
            let remotes = repo_db.list_repository_remotes().await?;
            if remotes.iter().any(|r| r.connection_id == id) {
                return Err(Error::InvalidConfig(format!(
                    "远程连接正在被仓库 '{}' 使用，无法删除",
                    repo.name
                )));
            }
        }
        
        self.db.delete_remote_connection(id).await
    }

    /// 测试连接
    pub async fn test_connection(&self, id: i64, test_path: Option<&str>) -> Result<ConnectionTestResult> {
        let conn = self.db.get_remote_connection(id).await?
            .ok_or(Error::RemoteConnectionNotFound(id))?;

        let protocol = conn.get_protocol()
            .map_err(|e| Error::InvalidConfig(e))?;

        match protocol {
            Protocol::Smb => self.test_smb_connection(&conn, test_path).await,
            Protocol::WebDav => self.test_webdav_connection(&conn, test_path).await,
            Protocol::Unc => self.test_unc_connection(&conn, test_path).await,
        }
    }

    /// 直接测试连接（不保存）
    pub async fn test_connection_direct(&self, request: &CreateRemoteConnectionRequest) -> Result<ConnectionTestResult> {
        let conn = RemoteConnection {
            id: 0,
            name: String::new(),
            protocol: request.protocol.to_string(),
            host: request.host.clone(),
            port: request.port,
            username: request.username.clone(),
            password: request.password.clone(),
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };

        match request.protocol {
            Protocol::Smb => self.test_smb_connection(&conn, None).await,
            Protocol::WebDav => self.test_webdav_connection(&conn, None).await,
            Protocol::Unc => self.test_unc_connection(&conn, None).await,
        }
    }

    /// 测试 SMB 连接
    async fn test_smb_connection(&self, conn: &RemoteConnection, _test_path: Option<&str>) -> Result<ConnectionTestResult> {
        let client = SmbClient::new(
            &conn.host,
            conn.port.unwrap_or(445) as u16,
            conn.username.as_deref(),
            conn.password.as_deref(),
        );

        let start = Instant::now();
        match client.connect().await {
            Ok(_) => {
                let latency_ms = start.elapsed().as_millis() as u64;
                Ok(ConnectionTestResult {
                    success: true,
                    message: "SMB 网络可达（当前未执行协议级共享与写入校验）".to_string(),
                    details: Some(ConnectionTestDetails {
                        can_read: true,
                        can_write: false,
                        can_list: false,
                        latency_ms: Some(latency_ms),
                        share_list: None,
                    }),
                })
            }
            Err(e) => Ok(ConnectionTestResult {
                success: false,
                message: format!("SMB 连接失败: {}", e),
                details: Some(ConnectionTestDetails {
                    can_read: false,
                    can_write: false,
                    can_list: false,
                    latency_ms: None,
                    share_list: None,
                }),
            }),
        }
    }

    /// 测试 WebDAV 连接
    async fn test_webdav_connection(&self, conn: &RemoteConnection, test_path: Option<&str>) -> Result<ConnectionTestResult> {
        let config = WebDavConfig::from_connection(conn, test_path.unwrap_or("/"));
        let client = WebDavClient::new(&config);
        client.test_connection(&config.path).await
    }

    /// 测试 UNC 连接
    async fn test_unc_connection(&self, conn: &RemoteConnection, _test_path: Option<&str>) -> Result<ConnectionTestResult> {
        let client = UncClient::new(&conn.host, None);
        let path = _test_path.unwrap_or("\\");

        match client.test_connection(path).await {
            Ok(_) => Ok(ConnectionTestResult {
                success: true,
                message: format!("UNC 路径可达: {}", client.unc_path(path)),
                details: Some(ConnectionTestDetails {
                    can_read: true,
                    can_write: true,
                    can_list: true,
                    latency_ms: None,
                    share_list: None,
                }),
            }),
            Err(e) => Ok(ConnectionTestResult {
                success: false,
                message: format!("UNC 路径不可达: {}", e),
                details: Some(ConnectionTestDetails {
                    can_read: false,
                    can_write: false,
                    can_list: false,
                    latency_ms: None,
                    share_list: None,
                }),
            }),
        }
    }
}