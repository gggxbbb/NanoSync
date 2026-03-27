//! 数据库模块
//!
//! 数据库设计遵循"仓库主权"原则：
//! - 软件级数据库只存储远程连接和已注册仓库清单
//! - 仓库级数据存储在各仓库的 .nanosync 目录中

pub mod schema;
pub mod manager;
pub mod repository;

pub use manager::DatabaseManager;
pub use repository::RepositoryDatabase;