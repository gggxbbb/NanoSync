//! 错误类型定义

use thiserror::Error;

#[derive(Error, Debug)]
pub enum Error {
    #[error("数据库错误: {0}")]
    Database(#[from] sqlx::Error),
    
    #[error("IO错误: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("序列化错误: {0}")]
    Serialization(#[from] serde_json::Error),
    
    #[error("仓库不存在: {0}")]
    RepositoryNotFound(i64),
    
    #[error("仓库路径不存在: {0}")]
    RepositoryPathNotFound(String),
    
    #[error("仓库已存在: {0}")]
    RepositoryAlreadyExists(String),
    
    #[error("远程连接不存在: {0}")]
    RemoteConnectionNotFound(i64),
    
    #[error("远程连接名称已存在: {0}")]
    RemoteConnectionNameExists(String),
    
    #[error("远程连接测试失败: {0}")]
    RemoteConnectionTestFailed(String),
    
    #[error("同步错误: {0}")]
    SyncFailed(String),
    
    #[error("推送被拒绝 - 远端有新提交，需要先 pull")]
    PushRejectedBehind,
    
    #[error("版本控制错误: {0}")]
    VersionControl(String),
    
    #[error("合并冲突: {0}")]
    MergeConflict(String),
    
    #[error("分支不存在: {0}")]
    BranchNotFound(String),
    
    #[error("提交不存在: {0}")]
    CommitNotFound(String),
    
    #[error("工作区有未提交的变更")]
    WorkingDirectoryDirty,
    
    #[error("自动化规则不存在: {0}")]
    AutomationRuleNotFound(i64),
    
    #[error("无效的配置: {0}")]
    InvalidConfig(String),
    
    #[error("IPC通信错误: {0}")]
    Ipc(String),
    
    #[error("权限不足: {0}")]
    PermissionDenied(String),
    
    #[error("路径无效: {0}")]
    InvalidPath(String),
    
    #[error("忽略规则解析错误: {0}")]
    IgnorePattern(String),
    
    #[error("SMB连接错误: {0}")]
    Smb(String),
    
    #[error("WebDAV连接错误: {0}")]
    WebDav(String),
    
    #[error("UNC路径错误: {0}")]
    Unc(String),
    
    #[error("未初始化: {0}")]
    NotInitialized(String),
    
    #[error("操作超时")]
    Timeout,
    
    #[error("未知错误: {0}")]
    Unknown(String),
}

pub type Result<T> = std::result::Result<T, Error>;

impl From<toml::de::Error> for Error {
    fn from(e: toml::de::Error) -> Self {
        Error::InvalidConfig(e.to_string())
    }
}

impl From<tokio::task::JoinError> for Error {
    fn from(e: tokio::task::JoinError) -> Self {
        Error::Unknown(e.to_string())
    }
}

impl From<chrono::ParseError> for Error {
    fn from(e: chrono::ParseError) -> Self {
        Error::InvalidConfig(format!("日期时间解析错误: {}", e))
    }
}
