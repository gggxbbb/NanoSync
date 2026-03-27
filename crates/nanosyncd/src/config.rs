//! 配置管理

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// 服务配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// 数据库路径
    pub database_path: PathBuf,
    
    /// IPC 端口/路径
    pub ipc_address: String,
    
    /// 日志级别
    pub log_level: String,
    
    /// 自动化 tick 间隔（秒）
    pub automation_tick_interval: u64,
    
    /// 同步超时（秒）
    pub sync_timeout: u64,
}

impl Default for Config {
    fn default() -> Self {
        let data_dir = directories::ProjectDirs::from("com", "nanosync", "nanosyncd")
            .map(|d| d.data_dir().to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."));
        
        Self {
            database_path: data_dir.join("nanosync.db"),
            ipc_address: default_ipc_address(),
            log_level: "info".to_string(),
            automation_tick_interval: 15,
            sync_timeout: 300,
        }
    }
}

#[cfg(windows)]
fn default_ipc_address() -> String {
    r"\\.\pipe\nanosyncd".to_string()
}

#[cfg(not(windows))]
fn default_ipc_address() -> String {
    "/tmp/nanosyncd.sock".to_string()
}

impl Config {
    /// 从文件加载配置
    pub fn load(path: &std::path::Path) -> anyhow::Result<Self> {
        if !path.exists() {
            return Ok(Self::default());
        }
        
        let content = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }
    
    /// 保存配置到文件
    pub fn save(&self, path: &std::path::Path) -> anyhow::Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
    
    /// 获取默认配置文件路径
    pub fn default_config_path() -> PathBuf {
        directories::ProjectDirs::from("com", "nanosync", "nanosyncd")
            .map(|d| d.config_dir().join("config.toml"))
            .unwrap_or_else(|| PathBuf::from("config.toml"))
    }
}