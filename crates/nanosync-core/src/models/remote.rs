//! 远程连接相关数据模型

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use std::str::FromStr;

/// 远程连接协议类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "TEXT")]
#[serde(rename_all = "lowercase")]
pub enum Protocol {
    Smb,
    WebDav,
    Unc,
}

impl std::fmt::Display for Protocol {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Protocol::Smb => write!(f, "smb"),
            Protocol::WebDav => write!(f, "webdav"),
            Protocol::Unc => write!(f, "unc"),
        }
    }
}

impl std::str::FromStr for Protocol {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "smb" => Ok(Protocol::Smb),
            "webdav" => Ok(Protocol::WebDav),
            "unc" => Ok(Protocol::Unc),
            _ => Err(format!("Unknown protocol: {}", s)),
        }
    }
}

/// 远程连接（软件级数据库）
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct RemoteConnection {
    pub id: i64,
    pub name: String,
    pub protocol: String,  // 存储为字符串
    pub host: String,
    pub port: Option<i32>,
    pub username: Option<String>,
    pub password: Option<String>,  // TODO: 考虑加密存储
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl RemoteConnection {
    pub fn get_protocol(&self) -> Result<Protocol, String> {
        Protocol::from_str(&self.protocol)
    }
}

/// 创建远程连接请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRemoteConnectionRequest {
    pub name: String,
    pub protocol: Protocol,
    pub host: String,
    pub port: Option<i32>,
    pub username: Option<String>,
    pub password: Option<String>,
}

/// 更新远程连接请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateRemoteConnectionRequest {
    pub id: i64,
    pub name: Option<String>,
    pub host: Option<String>,
    pub port: Option<i32>,
    pub username: Option<String>,
    pub password: Option<String>,
}

/// 连接测试结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionTestResult {
    pub success: bool,
    pub message: String,
    pub details: Option<ConnectionTestDetails>,
}

/// 连接测试详情
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionTestDetails {
    pub can_read: bool,
    pub can_write: bool,
    pub can_list: bool,
    pub latency_ms: Option<u64>,
    pub share_list: Option<Vec<String>>,  // SMB 专用
}

/// SMB 连接配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmbConfig {
    pub host: String,
    pub port: Option<i32>,
    pub username: String,
    pub password: String,
    pub share: String,
    pub path: String,
}

/// WebDAV 连接配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebDavConfig {
    pub host: String,
    pub port: Option<i32>,
    pub use_https: bool,
    pub username: Option<String>,
    pub password: Option<String>,
    pub path: String,
}

impl WebDavConfig {
    pub fn from_connection(conn: &RemoteConnection, path: &str) -> Self {
        let use_https = conn.port.map(|p| p == 443).unwrap_or(false);
        Self {
            host: conn.host.clone(),
            port: conn.port,
            use_https,
            username: conn.username.clone(),
            password: conn.password.clone(),
            path: path.to_string(),
        }
    }

    pub fn base_url(&self) -> String {
        let scheme = if self.use_https { "https" } else { "http" };
        let port = self.port.map(|p| format!(":{}", p)).unwrap_or_default();
        format!("{}://{}{}", scheme, self.host, port)
    }

    pub fn full_url(&self) -> String {
        let base = self.base_url();
        let path = self.path.trim_start_matches('/');
        format!("{}/{}", base, path)
    }
}

/// UNC 连接配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UncConfig {
    pub server: String,
    pub share: Option<String>,
    pub path: String,
}

impl UncConfig {
    pub fn full_path(&self) -> String {
        if let Some(share) = &self.share {
            format!("\\\\{}\\{}\\{}", self.server, share, self.path.trim_start_matches('\\'))
        } else {
            format!("\\\\{}\\{}", self.server, self.path.trim_start_matches('\\'))
        }
    }
}
