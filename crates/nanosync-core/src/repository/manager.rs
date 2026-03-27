//! 仓库管理器

use crate::database::{DatabaseManager, RepositoryDatabase};
use crate::device::DeviceIdentity;
use crate::error::{Error, Result};
use crate::models::*;
use crate::utils::path::*;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

/// 仓库管理器
pub struct RepositoryManager {
    db: Arc<DatabaseManager>,
    device_identity: DeviceIdentity,
    repo_databases: RwLock<std::collections::HashMap<i64, Arc<RepositoryDatabase>>>,
}

impl RepositoryManager {
    pub fn new(db: Arc<DatabaseManager>, device_identity: DeviceIdentity) -> Self {
        Self {
            db,
            device_identity,
            repo_databases: RwLock::new(std::collections::HashMap::new()),
        }
    }

    /// 列出所有仓库
    pub async fn list_repositories(&self) -> Result<Vec<RegisteredRepository>> {
        self.db.list_repositories().await
    }

    /// 获取单个仓库
    pub async fn get_repository(&self, id: i64) -> Result<Option<RegisteredRepository>> {
        self.db.get_repository(id).await
    }

    /// 通过路径获取仓库
    pub async fn get_repository_by_path(&self, path: &str) -> Result<Option<RegisteredRepository>> {
        self.db.get_repository_by_path(path).await
    }

    /// 导入仓库
    pub async fn import_repository(&self, options: &ImportRepositoryOptions) -> Result<RegisteredRepository> {
        let path = PathBuf::from(&options.path);
        
        // 验证路径存在
        if !path.exists() {
            return Err(Error::RepositoryPathNotFound(options.path.clone()));
        }

        // 检查是否已注册
        if let Some(existing) = self.get_repository_by_path(&options.path).await? {
            return Err(Error::RepositoryAlreadyExists(existing.local_path));
        }

        // 确定仓库名称
        let name = options.name.clone().unwrap_or_else(|| {
            path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unnamed")
                .to_string()
        });

        // 确保仓库目录结构
        ensure_repository_structure(&path)?;

        // 创建配置文件
        let config = RepositoryConfig {
            id: 0, // 将在注册后更新
            name: name.clone(),
            created_at: chrono::Utc::now(),
            device_fingerprint: self.device_identity.fingerprint.clone(),
            default_remote_name: None,
        };
        self.write_repository_config(&path, &config)?;

        // 创建忽略文件
        crate::utils::ignore::IgnoreManager::create_default_ignore_file(&path)?;

        // 注册到软件级数据库
        let repo = self.db.register_repository(&name, &options.path).await?;

        // 更新配置文件中的 ID
        let mut config = config;
        config.id = repo.id;
        self.write_repository_config(&path, &config)?;

        // 获取仓库数据库
        let repo_db = self.get_or_create_repo_database(repo.id, &path).await?;

        // 创建默认分支
        let default_branch_name = "main";
        let initial_commit_id = self.create_initial_commit(&repo_db, default_branch_name).await?;
        repo_db.create_branch(default_branch_name, &initial_commit_id, true).await?;

        // 保存默认本地设置
        let settings = options.settings.clone().unwrap_or_default();
        repo_db.save_local_settings(&settings).await?;

        // 绑定默认远端（如果指定）
        if let Some(remote_id) = options.bind_remote_id {
            let remote_path = options.bind_remote_path.clone().unwrap_or_default();
            let remote = RepositoryRemote {
                remote_name: "origin".to_string(),
                connection_id: remote_id,
                remote_path,
                is_default: true,
                last_sync: None,
                last_fetch: None,
                created_at: chrono::Utc::now(),
            };
            repo_db.add_repository_remote(&remote).await?;
        }

        info!("仓库导入成功: {} ({})", name, options.path);
        Ok(repo)
    }

    /// 注销仓库
    pub async fn unregister_repository(&self, id: i64, delete_nanosync_folder: bool) -> Result<()> {
        let repo = self.db.get_repository(id).await?
            .ok_or(Error::RepositoryNotFound(id))?;

        // 删除仓库数据库缓存
        let mut repos = self.repo_databases.write().await;
        repos.remove(&id);
        drop(repos);

        // 可选删除 .nanosync 文件夹
        if delete_nanosync_folder {
            let nanosync_path = nanosync_dir(Path::new(&repo.local_path));
            if nanosync_path.exists() {
                std::fs::remove_dir_all(&nanosync_path)?;
            }
        }

        // 从软件级数据库删除
        self.db.unregister_repository(id).await?;

        info!("仓库注销成功: {}", repo.name);
        Ok(())
    }

    /// 迁移仓库路径
    pub async fn migrate_repository(&self, id: i64, new_path: &str) -> Result<()> {
        let repo = self.db.get_repository(id).await?
            .ok_or(Error::RepositoryNotFound(id))?;

        let old_path = PathBuf::from(&repo.local_path);
        let new_path = PathBuf::from(new_path);

        // 验证新路径
        if !new_path.exists() {
            return Err(Error::RepositoryPathNotFound(new_path.to_string_lossy().to_string()));
        }

        // 移动 .nanosync 目录
        let old_nanosync = nanosync_dir(&old_path);
        let new_nanosync = nanosync_dir(&new_path);

        if old_nanosync.exists() {
            std::fs::rename(&old_nanosync, &new_nanosync)?;
        }

        // 更新数据库路径
        self.db.update_repository_path(id, new_path.to_string_lossy().as_ref()).await?;

        // 清除缓存
        let mut repos = self.repo_databases.write().await;
        repos.remove(&id);

        info!("仓库迁移成功: {} -> {}", repo.local_path, new_path.display());
        Ok(())
    }

    /// 获取仓库状态摘要
    pub async fn get_repository_status(&self, id: i64) -> Result<RepositoryStatus> {
        let repo = self.db.get_repository(id).await?
            .ok_or(Error::RepositoryNotFound(id))?;

        let repo_db = self.get_or_create_repo_database(id, Path::new(&repo.local_path)).await?;

        // 获取默认分支
        let default_branch = repo_db.get_default_branch().await?;
        
        // 获取暂存区和工作区状态
        let staged = repo_db.list_staged_entries().await?;
        
        // 获取远端信息
        let remotes = repo_db.list_repository_remotes().await?;
        let default_remote = remotes.iter().find(|r| r.is_default);
        
        // 计算 ahead/behind
        let (ahead, behind) = self.calculate_ahead_behind(&repo_db, &default_branch).await?;

        Ok(RepositoryStatus {
            repository_id: id,
            repository_name: repo.name.clone(),
            local_path: repo.local_path.clone(),
            default_remote_name: default_remote.map(|r| r.remote_name.clone()),
            ahead,
            behind,
            is_dirty: !staged.is_empty(), // 简化判断
            has_staged_changes: !staged.is_empty(),
            has_unstaged_changes: false, // 需要实际扫描
            has_conflicts: false,
            current_branch: default_branch.map(|b| b.name),
            last_sync: default_remote.and_then(|r| r.last_sync),
            last_fetch: default_remote.and_then(|r| r.last_fetch),
        })
    }

    /// 获取或创建仓库数据库
    async fn get_or_create_repo_database(&self, repo_id: i64, repo_path: &Path) -> Result<Arc<RepositoryDatabase>> {
        // 先检查缓存
        {
            let repos = self.repo_databases.read().await;
            if let Some(db) = repos.get(&repo_id) {
                return Ok(db.clone());
            }
        }

        // 创建新连接
        let db = Arc::new(RepositoryDatabase::open(repo_path, repo_id).await?);
        
        // 缓存
        {
            let mut repos = self.repo_databases.write().await;
            repos.insert(repo_id, db.clone());
        }

        Ok(db)
    }

    /// 写入仓库配置
    fn write_repository_config(&self, repo_path: &Path, config: &RepositoryConfig) -> Result<()> {
        let config_path = repository_config_path(repo_path);
        let content = serde_json::to_string_pretty(config)?;
        std::fs::write(&config_path, content)?;
        Ok(())
    }

    /// 创建初始提交
    async fn create_initial_commit(&self, repo_db: &RepositoryDatabase, branch_name: &str) -> Result<String> {
        let now = chrono::Utc::now();
        let commit_id = crate::utils::hash::generate_uuid();
        
        let commit = Commit {
            id: commit_id.clone(),
            repository_id: repo_db.repository_id,
            branch_name: branch_name.to_string(),
            parent_ids: vec![],
            message: "Initial commit".to_string(),
            author: self.device_identity.username.clone(),
            author_email: None,
            timestamp: now,
            tree_root: "empty".to_string(),
            created_at: now,
        };

        repo_db.add_commit(&commit).await?;
        Ok(commit_id)
    }

    /// 计算 ahead/behind
    async fn calculate_ahead_behind(&self, _repo_db: &RepositoryDatabase, branch: &Option<Branch>) -> Result<(i32, i32)> {
        // TODO: 实现真实的 ahead/behind 计算
        // 需要对比本地分支和远端跟踪分支
        Ok((0, 0))
    }
}