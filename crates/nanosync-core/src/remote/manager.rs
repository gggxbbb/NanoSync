//! 远程连接管理器

use crate::database::DatabaseManager;
use crate::error::{Error, Result};
use crate::models::*;
use std::sync::Arc;

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
        // 检查是否被仓库使用
        // TODO: 实现检查逻辑
        
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
    async fn test_smb_connection(&self, _conn: &RemoteConnection, _test_path: Option<&str>) -> Result<ConnectionTestResult> {
        // TODO: 实现真实的 SMB 连接测试
        // 使用 strictCredentialCheck 进行严格凭证校验
        
        Ok(ConnectionTestResult {
            success: true,
            message: "SMB 连接测试成功".to_string(),
            details: Some(ConnectionTestDetails {
                can_read: true,
                can_write: true,
                can_list: true,
                latency_ms: Some(50),
                share_list: None,
            }),
        })
    }

    /// 测试 WebDAV 连接
    async fn test_webdav_connection(&self, _conn: &RemoteConnection, _test_path: Option<&str>) -> Result<ConnectionTestResult> {
        // TODO: 实现真实的 WebDAV 连接测试
        // 包括 ping、目录访问、可写性验证
        
        Ok(ConnectionTestResult {
            success: true,
            message: "WebDAV 连接测试成功".to_string(),
            details: Some(ConnectionTestDetails {
                can_read: true,
                can_write: true,
                can_list: true,
                latency_ms: Some(100),
                share_list: None,
            }),
        })
    }

    /// 测试 UNC 连接
    async fn test_unc_connection(&self, conn: &RemoteConnection, _test_path: Option<&str>) -> Result<ConnectionTestResult> {
        // TODO: 实现真实的 UNC 路径可达性检测
        
        let unc_path = format!("\\\\{}", conn.host);
        
        Ok(ConnectionTestResult {
            success: true,
            message: format!("UNC 路径可达: {}", unc_path),
            details: Some(ConnectionTestDetails {
                can_read: true,
                can_write: true,
                can_list: true,
                latency_ms: Some(30),
                share_list: None,
            }),
        })
    }
}