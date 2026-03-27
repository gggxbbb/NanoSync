//! UNC 路径访问实现

use crate::error::{Error, Result};
use crate::models::*;
use std::path::PathBuf;

/// UNC 客户端
pub struct UncClient {
    server: String,
    share: Option<String>,
}

impl UncClient {
    pub fn new(server: &str, share: Option<&str>) -> Self {
        Self {
            server: server.to_string(),
            share: share.map(|s| s.to_string()),
        }
    }

    /// 从配置创建
    pub fn from_config(config: &UncConfig) -> Self {
        Self::new(&config.server, config.share.as_deref())
    }

    /// 获取 UNC 路径
    pub fn unc_path(&self, path: &str) -> String {
        let path = path.trim_start_matches('\\');
        if let Some(share) = &self.share {
            format!("\\\\{}\\{}\\{}", self.server, share, path)
        } else {
            format!("\\\\{}\\{}", self.server, path)
        }
    }

    /// 测试连接（路径可达性）
    pub async fn test_connection(&self, path: &str) -> Result<ConnectionTestResult> {
        let unc_path = self.unc_path(path);
        let path = PathBuf::from(&unc_path);

        // 检查路径是否存在
        let exists = path.exists();
        
        if exists {
            Ok(ConnectionTestResult {
                success: true,
                message: format!("UNC 路径可达: {}", unc_path),
                details: None,
            })
        } else {
            Err(Error::Unc(format!("UNC 路径不存在: {}", unc_path)))
        }
    }

    /// 下载文件
    pub async fn download_file(&self, remote_path: &str, local_path: &std::path::Path) -> Result<()> {
        let unc_path = self.unc_path(remote_path);
        let source = PathBuf::from(&unc_path);

        if !source.exists() {
            return Err(Error::Unc(format!("源文件不存在: {}", unc_path)));
        }

        std::fs::copy(&source, local_path)?;
        Ok(())
    }

    /// 上传文件
    pub async fn upload_file(&self, local_path: &std::path::Path, remote_path: &str) -> Result<()> {
        let unc_path = self.unc_path(remote_path);
        let dest = PathBuf::from(&unc_path);

        // 确保父目录存在
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }

        std::fs::copy(local_path, &dest)?;
        Ok(())
    }

    /// 确保目录存在
    pub async fn ensure_directory(&self, path: &str) -> Result<()> {
        let unc_path = self.unc_path(path);
        let dir = PathBuf::from(&unc_path);

        std::fs::create_dir_all(&dir)?;
        Ok(())
    }

    /// 删除文件
    pub async fn delete_file(&self, remote_path: &str) -> Result<()> {
        let unc_path = self.unc_path(remote_path);
        let path = PathBuf::from(&unc_path);

        if path.exists() {
            std::fs::remove_file(&path)?;
        }
        Ok(())
    }

    /// 列出目录
    pub async fn list_directory(&self, path: &str) -> Result<Vec<RemoteFileInfo>> {
        let unc_path = self.unc_path(path);
        let dir = PathBuf::from(&unc_path);

        if !dir.exists() {
            return Err(Error::Unc(format!("目录不存在: {}", unc_path)));
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
                modified_time: metadata.modified()
                    .ok()
                    .map(|t| chrono::DateTime::from(t)),
            });
        }

        Ok(entries)
    }

    /// 检查文件是否存在
    pub fn file_exists(&self, remote_path: &str) -> bool {
        let unc_path = self.unc_path(remote_path);
        PathBuf::from(&unc_path).exists()
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