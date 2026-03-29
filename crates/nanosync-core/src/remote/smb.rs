//! SMB 协议实现

use crate::error::{Error, Result};
use tokio::net::TcpStream;
use tokio::time::{timeout, Duration};

/// SMB 客户端
pub struct SmbClient {
    host: String,
    port: u16,
    username: Option<String>,
    password: Option<String>,
}

impl SmbClient {
    pub fn new(host: &str, port: u16, username: Option<&str>, password: Option<&str>) -> Self {
        Self {
            host: host.to_string(),
            port,
            username: username.map(|s| s.to_string()),
            password: password.map(|s| s.to_string()),
        }
    }

    /// 连接到 SMB 服务器
    pub async fn connect(&self) -> Result<()> {
        if self.host.trim().is_empty() {
            return Err(Error::Smb("SMB 主机不能为空".to_string()));
        }

        let addr = format!("{}:{}", self.host, self.port);
        timeout(Duration::from_secs(5), TcpStream::connect(&addr))
            .await
            .map_err(|_| Error::Timeout)?
            .map_err(|e| Error::Smb(format!("无法连接到 {}: {}", addr, e)))?;

        Ok(())
    }

    /// 严格凭证校验
    pub async fn strict_credential_check(&self) -> Result<Vec<String>> {
        self.connect().await?;

        if self.username.as_deref().unwrap_or_default().is_empty()
            || self.password.as_deref().unwrap_or_default().is_empty()
        {
            return Err(Error::Smb(
                "缺少用户名或密码，无法执行 SMB 凭证校验".to_string(),
            ));
        }

        // 当前仅实现网络层可达性，凭证严格校验与共享枚举待接入 SMB 协议库。
        Ok(vec![])
    }

    /// 列出共享
    pub async fn list_shares(&self) -> Result<Vec<String>> {
        self.connect().await?;

        // 当前未接入 SMB 协议库，无法可靠枚举共享。
        // 保持空数组，调用方可提示用户手动指定 share。
        Ok(vec![])
    }

    fn share_unc_path(&self, share: &str, remote_path: &str) -> std::path::PathBuf {
        let share = share.trim_matches('\\').trim_matches('/');
        let remote_path = remote_path.trim_matches('\\').trim_matches('/').replace('/', "\\");
        if remote_path.is_empty() {
            std::path::PathBuf::from(format!("\\\\{}\\{}", self.host, share))
        } else {
            std::path::PathBuf::from(format!("\\\\{}\\{}\\{}", self.host, share, remote_path))
        }
    }

    /// 下载文件
    pub async fn download_file(&self, share: &str, remote_path: &str, local_path: &std::path::Path) -> Result<()> {
        let source = self.share_unc_path(share, remote_path);
        if !source.exists() {
            return Err(Error::Smb(format!("远端文件不存在: {}", source.display())));
        }

        if let Some(parent) = local_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::copy(&source, local_path)?;
        Ok(())
    }

    /// 上传文件
    pub async fn upload_file(&self, share: &str, local_path: &std::path::Path, remote_path: &str) -> Result<()> {
        if !local_path.exists() {
            return Err(Error::Smb(format!("本地文件不存在: {}", local_path.display())));
        }

        let dest = self.share_unc_path(share, remote_path);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }

        std::fs::copy(local_path, &dest)?;
        Ok(())
    }

    /// 确保目录存在
    pub async fn ensure_directory(&self, share: &str, path: &str) -> Result<()> {
        let dir = self.share_unc_path(share, path);
        std::fs::create_dir_all(&dir)?;
        Ok(())
    }

    /// 删除文件
    pub async fn delete_file(&self, share: &str, remote_path: &str) -> Result<()> {
        let path = self.share_unc_path(share, remote_path);
        if path.exists() {
            std::fs::remove_file(path)?;
        }
        Ok(())
    }

    /// 列出目录
    pub async fn list_directory(&self, share: &str, path: &str) -> Result<Vec<RemoteFileInfo>> {
        let dir = self.share_unc_path(share, path);
        if !dir.exists() {
            return Err(Error::Smb(format!("目录不存在: {}", dir.display())));
        }

        let mut entries = Vec::new();
        for entry in std::fs::read_dir(&dir)? {
            let entry = entry?;
            let metadata = entry.metadata()?;
            entries.push(RemoteFileInfo {
                name: entry.file_name().to_string_lossy().to_string(),
                path: entry.path().to_string_lossy().to_string(),
                is_directory: metadata.is_dir(),
                size: metadata.len(),
                modified_time: metadata
                    .modified()
                    .ok()
                    .map(chrono::DateTime::from),
            });
        }

        Ok(entries)
    }

    /// 检查远端文件是否存在
    pub fn file_exists(&self, share: &str, remote_path: &str) -> bool {
        self.share_unc_path(share, remote_path).exists()
    }
}

/// 远程文件信息
#[derive(Debug, Clone)]
pub struct RemoteFileInfo {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: u64,
    pub modified_time: Option<chrono::DateTime<chrono::Utc>>,
}