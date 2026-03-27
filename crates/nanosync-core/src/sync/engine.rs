//! 同步引擎实现

use crate::database::{DatabaseManager, RepositoryDatabase};
use crate::device::DeviceIdentity;
use crate::error::{Error, Result};
use crate::models::*;
use crate::repository::RepositoryManager;
use crate::remote::RemoteConnectionManager;
use std::path::Path;
use std::sync::Arc;
use tracing::info;

/// 同步引擎
pub struct SyncEngine {
    db: Arc<DatabaseManager>,
    repo_manager: Arc<RepositoryManager>,
    remote_manager: Arc<RemoteConnectionManager>,
    device_identity: DeviceIdentity,
}

impl SyncEngine {
    pub fn new(
        db: Arc<DatabaseManager>,
        repo_manager: Arc<RepositoryManager>,
        remote_manager: Arc<RemoteConnectionManager>,
        device_identity: DeviceIdentity,
    ) -> Self {
        Self {
            db,
            repo_manager,
            remote_manager,
            device_identity,
        }
    }

    /// Fetch 远端状态
    pub async fn fetch(
        &self,
        repository_id: i64,
        remote_name: Option<&str>,
        _record_log: bool,
    ) -> Result<FetchResult> {
        let start_time = std::time::Instant::now();
        let _sync_id = crate::utils::hash::generate_uuid();

        info!("开始 fetch: 仓库 {}, 远端 {:?}", repository_id, remote_name);

        // 获取仓库信息
        let repo = self.repo_manager.get_repository(repository_id).await?
            .ok_or(Error::RepositoryNotFound(repository_id))?;

        let repo_path = Path::new(&repo.local_path);
        let repo_db = self.get_repo_db(repository_id, repo_path).await?;

        // 获取默认远端
        let remotes = repo_db.list_repository_remotes().await?;
        let remote = if let Some(name) = remote_name {
            remotes.iter().find(|r| &r.remote_name == name)
        } else {
            remotes.iter().find(|r| r.is_default)
        };

        let remote = remote.ok_or_else(|| Error::SyncFailed("没有配置远端".to_string()))?;

        // 获取远程连接信息
        let _conn = self.remote_manager.get_connection(remote.connection_id).await?
            .ok_or(Error::RemoteConnectionNotFound(remote.connection_id))?;

        // TODO: 实现真实的 fetch 逻辑
        // 1. 下载远端 repository_state.json
        // 2. 导入远端状态
        // 3. 计算 ahead/behind
        // 4. 更新 last_fetch

        // 更新远端同步时间
        repo_db.update_remote_sync_time(&remote.remote_name, true).await?;

        let duration_ms = start_time.elapsed().as_millis() as u64;
        
        info!("Fetch 完成: {}ms", duration_ms);

        Ok(FetchResult {
            repository_id,
            remote_name: remote.remote_name.clone(),
            ahead: 0,
            behind: 0,
            fetched_objects: 0,
            fetched_size: 0,
            duration_ms,
            success: true,
            error_message: None,
        })
    }

    /// Push 到远端
    pub async fn push(
        &self,
        repository_id: i64,
        remote_name: Option<&str>,
        force: bool,
        _record_log: bool,
    ) -> Result<PushResult> {
        let start_time = std::time::Instant::now();

        info!("开始 push: 仓库 {}, 远端 {:?}", repository_id, remote_name);

        // 先 fetch 检查状态
        let fetch_result = self.fetch(repository_id, remote_name, false).await?;

        // 如果 behind > 0 且非 force，拒绝推送
        if fetch_result.behind > 0 && !force {
            return Err(Error::PushRejectedBehind);
        }

        // TODO: 实现真实的 push 逻辑
        // 1. 收集需要上传的对象
        // 2. 上传 objects
        // 3. 导出并上传 repository_state
        // 4. 更新 last_sync

        let duration_ms = start_time.elapsed().as_millis() as u64;
        
        info!("Push 完成: {}ms", duration_ms);

        Ok(PushResult {
            repository_id,
            remote_name: fetch_result.remote_name,
            pushed_commits: 0,
            pushed_objects: 0,
            pushed_size: 0,
            duration_ms,
            success: true,
            rejected: false,
            error_message: None,
        })
    }

    /// Pull 从远端
    pub async fn pull(
        &self,
        repository_id: i64,
        remote_name: Option<&str>,
        _record_log: bool,
    ) -> Result<PullResult> {
        let start_time = std::time::Instant::now();

        info!("开始 pull: 仓库 {}, 远端 {:?}", repository_id, remote_name);

        // 先 fetch 检查状态
        let fetch_result = self.fetch(repository_id, remote_name, false).await?;

        // 如果 behind == 0，无需操作
        if fetch_result.behind == 0 {
            return Ok(PullResult {
                repository_id,
                remote_name: fetch_result.remote_name,
                pulled_commits: 0,
                pulled_objects: 0,
                pulled_size: 0,
                fast_forwarded: true,
                merged: false,
                conflicts: 0,
                duration_ms: start_time.elapsed().as_millis() as u64,
                success: true,
                error_message: None,
            });
        }

        // TODO: 实现真实的 pull 逻辑
        // 1. 下载缺失 objects
        // 2. 检查工作区状态
        // 3. 执行 merge 或 fast-forward

        let duration_ms = start_time.elapsed().as_millis() as u64;
        
        info!("Pull 完成: {}ms", duration_ms);

        Ok(PullResult {
            repository_id,
            remote_name: fetch_result.remote_name,
            pulled_commits: 0,
            pulled_objects: 0,
            pulled_size: 0,
            fast_forwarded: true,
            merged: false,
            conflicts: 0,
            duration_ms,
            success: true,
            error_message: None,
        })
    }

    /// Sync (fetch + push 或 fetch + pull)
    pub async fn sync(
        &self,
        repository_id: i64,
        remote_name: Option<&str>,
        record_log: bool,
    ) -> Result<SyncResult> {
        let start_time = std::time::Instant::now();

        info!("开始 sync: 仓库 {}", repository_id);

        // 先 fetch
        let fetch_result = self.fetch(repository_id, remote_name, false).await?;

        // 根据状态决定 push 还是 pull
        let (push_result, pull_result) = if fetch_result.ahead > 0 && fetch_result.behind == 0 {
            // 只有 ahead，可以 push
            let push_result = self.push(repository_id, remote_name, false, record_log).await?;
            (Some(push_result), None)
        } else if fetch_result.behind > 0 {
            // 有 behind，需要 pull
            let pull_result = self.pull(repository_id, remote_name, record_log).await?;
            (None, Some(pull_result))
        } else {
            // 已经同步
            (None, None)
        };

        let duration_ms = start_time.elapsed().as_millis() as u64;
        let overall_success = push_result.as_ref().map(|r| r.success).unwrap_or(true)
            && pull_result.as_ref().map(|r| r.success).unwrap_or(true);

        info!("Sync 完成: {}ms, 成功: {}", duration_ms, overall_success);

        let remote_name = fetch_result.remote_name.clone();
        Ok(SyncResult {
            repository_id,
            remote_name,
            fetch_result,
            push_result,
            pull_result,
            overall_success,
            duration_ms,
        })
    }

    /// 获取同步状态
    pub async fn get_sync_status(&self, _repository_id: i64) -> Result<AheadBehind> {
        // TODO: 实现真实的 ahead/behind 计算
        Ok(AheadBehind {
            ahead: 0,
            behind: 0,
            ahead_commits: vec![],
            behind_commits: vec![],
        })
    }

    /// 获取仓库数据库
    async fn get_repo_db(&self, repo_id: i64, repo_path: &Path) -> Result<Arc<RepositoryDatabase>> {
        let db = RepositoryDatabase::open(repo_path, repo_id).await?;
        Ok(Arc::new(db))
    }
}