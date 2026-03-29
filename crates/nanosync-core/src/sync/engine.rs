//! 同步引擎实现

use crate::database::{DatabaseManager, RepositoryDatabase};
use crate::device::DeviceIdentity;
use crate::error::{Error, Result};
use crate::models::*;
use crate::repository::RepositoryManager;
use crate::remote::RemoteConnectionManager;
use crate::remote::smb::SmbClient;
use crate::remote::unc::UncClient;
use crate::remote::webdav::WebDavClient;
use crate::utils::path::{ensure_object_parent_dir, object_path};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RemoteObjectEntry {
    hash: String,
    size: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RemoteObjectIndex {
    generated_at: chrono::DateTime<chrono::Utc>,
    objects: Vec<RemoteObjectEntry>,
}

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
        let conn = self.remote_manager.get_connection(remote.connection_id).await?
            .ok_or(Error::RemoteConnectionNotFound(remote.connection_id))?;

        let local_head = self.local_head_commit_id(&repo_db).await?;
        let remote_state = self.fetch_remote_repository_state(&conn, &remote.remote_path).await?;
        let remote_head = remote_state.as_ref().map(|s| s.head_commit_id.clone());
        let ahead_behind = Self::calculate_ahead_behind(local_head.as_deref(), remote_head.as_deref());
        let (fetched_objects, fetched_size) = self
            .fetch_remote_objects(&conn, &remote.remote_path, repo_path, &repo_db)
            .await?;

        // 更新远端同步时间
        repo_db.update_remote_sync_time(&remote.remote_name, true).await?;

        let duration_ms = start_time.elapsed().as_millis() as u64;
        
        info!("Fetch 完成: {}ms", duration_ms);

        Ok(FetchResult {
            repository_id,
            remote_name: remote.remote_name.clone(),
            ahead: ahead_behind.ahead,
            behind: ahead_behind.behind,
            fetched_objects,
            fetched_size,
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

        let repo = self.repo_manager.get_repository(repository_id).await?
            .ok_or(Error::RepositoryNotFound(repository_id))?;
        let repo_path = Path::new(&repo.local_path);
        let repo_db = self.get_repo_db(repository_id, repo_path).await?;

        let remotes = repo_db.list_repository_remotes().await?;
        let remote = if let Some(name) = remote_name {
            remotes.iter().find(|r| r.remote_name == name)
        } else {
            remotes.iter().find(|r| r.is_default)
        }
        .ok_or_else(|| Error::SyncFailed("没有配置远端".to_string()))?;

        let conn = self.remote_manager.get_connection(remote.connection_id).await?
            .ok_or(Error::RemoteConnectionNotFound(remote.connection_id))?;

        let (pushed_objects, pushed_size) = self
            .push_local_objects(&conn, &remote.remote_path, repo_path, &repo_db)
            .await?;
        let state = self.build_local_repository_state(&repo_db).await?;
        self.push_remote_repository_state(&conn, &remote.remote_path, &state).await?;
        repo_db.update_remote_sync_time(&remote.remote_name, false).await?;

        let duration_ms = start_time.elapsed().as_millis() as u64;
        
        info!("Push 完成: {}ms", duration_ms);

        Ok(PushResult {
            repository_id,
            remote_name: fetch_result.remote_name,
            pushed_commits: 0,
            pushed_objects,
            pushed_size,
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
                pulled_objects: fetch_result.fetched_objects,
                pulled_size: fetch_result.fetched_size,
                fast_forwarded: true,
                merged: false,
                conflicts: 0,
                duration_ms: start_time.elapsed().as_millis() as u64,
                success: true,
                error_message: None,
            });
        }

        // 当前 pull 最小实现：依赖 fetch 阶段下载缺失 objects。
        // 合并/快进逻辑后续补全。
        let repo = self.repo_manager.get_repository(repository_id).await?
            .ok_or(Error::RepositoryNotFound(repository_id))?;
        let repo_path = Path::new(&repo.local_path);
        let repo_db = self.get_repo_db(repository_id, repo_path).await?;

        let remotes = repo_db.list_repository_remotes().await?;
        let remote = if let Some(name) = remote_name {
            remotes.iter().find(|r| r.remote_name == name)
        } else {
            remotes.iter().find(|r| r.is_default)
        }
        .ok_or_else(|| Error::SyncFailed("没有配置远端".to_string()))?;

        let conn = self.remote_manager.get_connection(remote.connection_id).await?
            .ok_or(Error::RemoteConnectionNotFound(remote.connection_id))?;

        if let Some(remote_state) = self
            .fetch_remote_repository_state(&conn, &remote.remote_path)
            .await?
        {
            self.apply_remote_repository_state(&repo_db, &remote_state).await?;
        }

        let duration_ms = start_time.elapsed().as_millis() as u64;
        
        info!("Pull 完成: {}ms", duration_ms);

        Ok(PullResult {
            repository_id,
            remote_name: fetch_result.remote_name,
            pulled_commits: 0,
            pulled_objects: fetch_result.fetched_objects,
            pulled_size: fetch_result.fetched_size,
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
        let fetch_result = self.fetch(_repository_id, None, false).await?;
        Ok(AheadBehind {
            ahead: fetch_result.ahead,
            behind: fetch_result.behind,
            ahead_commits: vec![],
            behind_commits: vec![],
        })
    }

    /// 获取仓库数据库
    async fn get_repo_db(&self, repo_id: i64, repo_path: &Path) -> Result<Arc<RepositoryDatabase>> {
        let db = RepositoryDatabase::open(repo_path, repo_id).await?;
        Ok(Arc::new(db))
    }

    async fn local_head_commit_id(&self, repo_db: &RepositoryDatabase) -> Result<Option<String>> {
        Ok(repo_db
            .get_default_branch()
            .await?
            .map(|b| b.head_commit_id)
            .filter(|s| !s.is_empty()))
    }

    fn remote_state_candidate_paths(remote_base: &str) -> Vec<String> {
        let base = remote_base.trim_matches('/').replace('\\', "/");
        if base.is_empty() {
            return vec![
                ".nanosync/repository_state.json".to_string(),
                "repository_state.json".to_string(),
            ];
        }

        vec![
            format!("{}/.nanosync/repository_state.json", base),
            format!("{}/repository_state.json", base),
        ]
    }

    fn remote_object_index_path(remote_base: &str) -> String {
        let base = remote_base.trim_matches('/').replace('\\', "/");
        if base.is_empty() {
            ".nanosync/object_index.json".to_string()
        } else {
            format!("{}/.nanosync/object_index.json", base)
        }
    }

    fn remote_object_path(remote_base: &str, hash: &str) -> String {
        let base = remote_base.trim_matches('/').replace('\\', "/");
        if hash.len() < 3 {
            if base.is_empty() {
                return format!(".nanosync/objects/{}", hash);
            }
            return format!("{}/.nanosync/objects/{}", base, hash);
        }

        let sub = &hash[..2];
        let rest = &hash[2..];
        if base.is_empty() {
            format!(".nanosync/objects/{}/{}", sub, rest)
        } else {
            format!("{}/.nanosync/objects/{}/{}", base, sub, rest)
        }
    }

    fn parse_smb_share_and_base_path(remote_base: &str) -> Result<(String, String)> {
        let normalized = remote_base.trim_matches('/').replace('\\', "/");
        let mut parts = normalized.split('/').filter(|p| !p.is_empty());
        let share = parts
            .next()
            .ok_or_else(|| Error::InvalidPath("SMB 远端路径必须包含 share，例如 /public 或 /public/folder".to_string()))?
            .to_string();
        let rest = parts.collect::<Vec<_>>().join("/");
        Ok((share, rest))
    }

    async fn fetch_remote_repository_state(
        &self,
        conn: &RemoteConnection,
        remote_base: &str,
    ) -> Result<Option<RepositoryState>> {
        let protocol = conn
            .get_protocol()
            .map_err(|e| Error::InvalidConfig(e.to_string()))?;

        match protocol {
            Protocol::WebDav => {
                let config = WebDavConfig::from_connection(conn, "/");
                let client = WebDavClient::new(&config);
                let candidates = Self::remote_state_candidate_paths(remote_base);

                for remote_path in candidates {
                    if !client.file_exists(&remote_path).await? {
                        continue;
                    }

                    let temp_path = std::env::temp_dir().join(format!(
                        "nanosync-fetch-{}.json",
                        crate::utils::hash::generate_uuid()
                    ));
                    client.download_file(&remote_path, &temp_path).await?;
                    let content = std::fs::read_to_string(&temp_path)?;
                    let _ = std::fs::remove_file(&temp_path);
                    let state: RepositoryState = serde_json::from_str(&content)?;
                    return Ok(Some(state));
                }

                Ok(None)
            }
            Protocol::Unc => {
                let client = UncClient::new(&conn.host, None);
                let candidates = Self::remote_state_candidate_paths(remote_base);

                for remote_path in candidates {
                    let unc_rel = remote_path.replace('/', "\\");
                    if !client.file_exists(&unc_rel) {
                        continue;
                    }

                    let temp_path = std::env::temp_dir().join(format!(
                        "nanosync-fetch-{}.json",
                        crate::utils::hash::generate_uuid()
                    ));
                    client.download_file(&unc_rel, &temp_path).await?;
                    let content = std::fs::read_to_string(&temp_path)?;
                    let _ = std::fs::remove_file(&temp_path);
                    let state: RepositoryState = serde_json::from_str(&content)?;
                    return Ok(Some(state));
                }

                Ok(None)
            }
            Protocol::Smb => {
                let (share, base_path) = Self::parse_smb_share_and_base_path(remote_base)?;
                let client = SmbClient::new(
                    &conn.host,
                    conn.port.unwrap_or(445) as u16,
                    conn.username.as_deref(),
                    conn.password.as_deref(),
                );
                let candidates = Self::remote_state_candidate_paths(&base_path);

                for remote_path in candidates {
                    let temp_path = std::env::temp_dir().join(format!(
                        "nanosync-fetch-{}.json",
                        crate::utils::hash::generate_uuid()
                    ));
                    if client.download_file(&share, &remote_path, &temp_path).await.is_err() {
                        continue;
                    }
                    let content = std::fs::read_to_string(&temp_path)?;
                    let _ = std::fs::remove_file(&temp_path);
                    let state: RepositoryState = serde_json::from_str(&content)?;
                    return Ok(Some(state));
                }

                Ok(None)
            }
        }
    }

    async fn build_local_repository_state(
        &self,
        repo_db: &RepositoryDatabase,
    ) -> Result<RepositoryState> {
        let branches = repo_db.list_branches().await?;
        let default_branch = branches.iter().find(|b| b.is_default);

        let current_branch = default_branch
            .map(|b| b.name.clone())
            .unwrap_or_else(|| "main".to_string());
        let head_commit_id = default_branch
            .map(|b| b.head_commit_id.clone())
            .unwrap_or_default();

        let branch_states = branches
            .into_iter()
            .map(|b| BranchState {
                name: b.name,
                head_commit_id: b.head_commit_id,
                is_default: b.is_default,
            })
            .collect();

        Ok(RepositoryState {
            head_commit_id,
            current_branch,
            branches: branch_states,
            last_export: Some(chrono::Utc::now()),
        })
    }

    async fn push_remote_repository_state(
        &self,
        conn: &RemoteConnection,
        remote_base: &str,
        state: &RepositoryState,
    ) -> Result<()> {
        let protocol = conn
            .get_protocol()
            .map_err(|e| Error::InvalidConfig(e.to_string()))?;

        let temp_path = std::env::temp_dir().join(format!(
            "nanosync-push-{}.json",
            crate::utils::hash::generate_uuid()
        ));
        std::fs::write(&temp_path, serde_json::to_vec_pretty(state)?)?;

        let remote_state_path = if remote_base.trim().is_empty() {
            ".nanosync/repository_state.json".to_string()
        } else {
            format!(
                "{}/.nanosync/repository_state.json",
                remote_base.trim_matches('/').replace('\\', "/")
            )
        };

        let result = match protocol {
            Protocol::WebDav => {
                let config = WebDavConfig::from_connection(conn, "/");
                let client = WebDavClient::new(&config);
                if let Some(parent) = remote_state_path.rsplit_once('/') {
                    client.ensure_directory(parent.0).await?;
                }
                client.upload_file(&temp_path, &remote_state_path).await
            }
            Protocol::Unc => {
                let client = UncClient::new(&conn.host, None);
                let unc_path = remote_state_path.replace('/', "\\");
                if let Some(parent) = unc_path.rsplit_once('\\') {
                    client.ensure_directory(parent.0).await?;
                }
                client.upload_file(&temp_path, &unc_path).await
            }
            Protocol::Smb => {
                let (share, base_path) = Self::parse_smb_share_and_base_path(remote_base)?;
                let client = SmbClient::new(
                    &conn.host,
                    conn.port.unwrap_or(445) as u16,
                    conn.username.as_deref(),
                    conn.password.as_deref(),
                );

                let smb_state_path = if base_path.is_empty() {
                    ".nanosync/repository_state.json".to_string()
                } else {
                    format!("{}/.nanosync/repository_state.json", base_path)
                };

                if let Some(parent) = smb_state_path.rsplit_once('/') {
                    client.ensure_directory(&share, parent.0).await?;
                }
                client.upload_file(&share, &temp_path, &smb_state_path).await
            }
        };

        let _ = std::fs::remove_file(&temp_path);
        result
    }

    async fn push_local_objects(
        &self,
        conn: &RemoteConnection,
        remote_base: &str,
        repo_path: &Path,
        repo_db: &RepositoryDatabase,
    ) -> Result<(i32, i64)> {
        let protocol = conn
            .get_protocol()
            .map_err(|e| Error::InvalidConfig(e.to_string()))?;

        let index = repo_db.get_object_index().await?;
        let mut map = std::collections::HashMap::<String, i64>::new();
        for entry in index {
            map.entry(entry.object_hash).or_insert(entry.file_size);
        }
        let objects: Vec<RemoteObjectEntry> = map
            .into_iter()
            .map(|(hash, size)| RemoteObjectEntry { hash, size })
            .collect();

        let mut pushed_objects = 0_i32;
        let mut pushed_size = 0_i64;

        match protocol {
            Protocol::WebDav => {
                let config = WebDavConfig::from_connection(conn, "/");
                let client = WebDavClient::new(&config);

                for obj in &objects {
                    let local_path = object_path(repo_path, &obj.hash);
                    if !local_path.exists() {
                        continue;
                    }

                    let remote_path = Self::remote_object_path(remote_base, &obj.hash);
                    if client.file_exists(&remote_path).await.unwrap_or(false) {
                        continue;
                    }

                    if let Some(parent) = remote_path.rsplit_once('/') {
                        client.ensure_directory(parent.0).await?;
                    }
                    client.upload_file(&local_path, &remote_path).await?;
                    pushed_objects += 1;
                    pushed_size += obj.size;
                }

                let index_path = Self::remote_object_index_path(remote_base);
                let index_content = RemoteObjectIndex {
                    generated_at: chrono::Utc::now(),
                    objects,
                };
                let temp_path = std::env::temp_dir().join(format!(
                    "nanosync-object-index-{}.json",
                    crate::utils::hash::generate_uuid()
                ));
                std::fs::write(&temp_path, serde_json::to_vec_pretty(&index_content)?)?;
                if let Some(parent) = index_path.rsplit_once('/') {
                    client.ensure_directory(parent.0).await?;
                }
                client.upload_file(&temp_path, &index_path).await?;
                let _ = std::fs::remove_file(&temp_path);
            }
            Protocol::Unc => {
                let client = UncClient::new(&conn.host, None);

                for obj in &objects {
                    let local_path = object_path(repo_path, &obj.hash);
                    if !local_path.exists() {
                        continue;
                    }

                    let remote_path = Self::remote_object_path(remote_base, &obj.hash).replace('/', "\\");
                    if client.file_exists(&remote_path) {
                        continue;
                    }

                    if let Some(parent) = remote_path.rsplit_once('\\') {
                        client.ensure_directory(parent.0).await?;
                    }
                    client.upload_file(&local_path, &remote_path).await?;
                    pushed_objects += 1;
                    pushed_size += obj.size;
                }

                let index_path = Self::remote_object_index_path(remote_base).replace('/', "\\");
                let index_content = RemoteObjectIndex {
                    generated_at: chrono::Utc::now(),
                    objects,
                };
                let temp_path = std::env::temp_dir().join(format!(
                    "nanosync-object-index-{}.json",
                    crate::utils::hash::generate_uuid()
                ));
                std::fs::write(&temp_path, serde_json::to_vec_pretty(&index_content)?)?;
                if let Some(parent) = index_path.rsplit_once('\\') {
                    client.ensure_directory(parent.0).await?;
                }
                client.upload_file(&temp_path, &index_path).await?;
                let _ = std::fs::remove_file(&temp_path);
            }
            Protocol::Smb => {
                let (share, base_path) = Self::parse_smb_share_and_base_path(remote_base)?;
                let client = SmbClient::new(
                    &conn.host,
                    conn.port.unwrap_or(445) as u16,
                    conn.username.as_deref(),
                    conn.password.as_deref(),
                );

                for obj in &objects {
                    let local_path = object_path(repo_path, &obj.hash);
                    if !local_path.exists() {
                        continue;
                    }

                    let remote_path = Self::remote_object_path(&base_path, &obj.hash);
                    if let Some(parent) = remote_path.rsplit_once('/') {
                        client.ensure_directory(&share, parent.0).await?;
                    }
                    client.upload_file(&share, &local_path, &remote_path).await?;
                    pushed_objects += 1;
                    pushed_size += obj.size;
                }

                let index_path = Self::remote_object_index_path(&base_path);
                let index_content = RemoteObjectIndex {
                    generated_at: chrono::Utc::now(),
                    objects,
                };
                let temp_path = std::env::temp_dir().join(format!(
                    "nanosync-object-index-{}.json",
                    crate::utils::hash::generate_uuid()
                ));
                std::fs::write(&temp_path, serde_json::to_vec_pretty(&index_content)?)?;
                if let Some(parent) = index_path.rsplit_once('/') {
                    client.ensure_directory(&share, parent.0).await?;
                }
                client.upload_file(&share, &temp_path, &index_path).await?;
                let _ = std::fs::remove_file(&temp_path);
            }
        }

        Ok((pushed_objects, pushed_size))
    }

    async fn fetch_remote_objects(
        &self,
        conn: &RemoteConnection,
        remote_base: &str,
        repo_path: &Path,
        _repo_db: &RepositoryDatabase,
    ) -> Result<(i32, i64)> {
        let protocol = conn
            .get_protocol()
            .map_err(|e| Error::InvalidConfig(e.to_string()))?;

        let mut fetched_objects = 0_i32;
        let mut fetched_size = 0_i64;

        match protocol {
            Protocol::WebDav => {
                let config = WebDavConfig::from_connection(conn, "/");
                let client = WebDavClient::new(&config);
                let index_path = Self::remote_object_index_path(remote_base);
                if !client.file_exists(&index_path).await.unwrap_or(false) {
                    return Ok((0, 0));
                }

                let temp_index = std::env::temp_dir().join(format!(
                    "nanosync-fetch-index-{}.json",
                    crate::utils::hash::generate_uuid()
                ));
                client.download_file(&index_path, &temp_index).await?;
                let content = std::fs::read_to_string(&temp_index)?;
                let _ = std::fs::remove_file(&temp_index);
                let remote_index: RemoteObjectIndex = serde_json::from_str(&content)?;

                for obj in remote_index.objects {
                    let local_obj = object_path(repo_path, &obj.hash);
                    if local_obj.exists() {
                        continue;
                    }
                    ensure_object_parent_dir(repo_path, &obj.hash)?;
                    let remote_obj_path = Self::remote_object_path(remote_base, &obj.hash);
                    client.download_file(&remote_obj_path, &local_obj).await?;
                    fetched_objects += 1;
                    fetched_size += obj.size;
                }
            }
            Protocol::Unc => {
                let client = UncClient::new(&conn.host, None);
                let index_path = Self::remote_object_index_path(remote_base).replace('/', "\\");
                if !client.file_exists(&index_path) {
                    return Ok((0, 0));
                }

                let temp_index = std::env::temp_dir().join(format!(
                    "nanosync-fetch-index-{}.json",
                    crate::utils::hash::generate_uuid()
                ));
                client.download_file(&index_path, &temp_index).await?;
                let content = std::fs::read_to_string(&temp_index)?;
                let _ = std::fs::remove_file(&temp_index);
                let remote_index: RemoteObjectIndex = serde_json::from_str(&content)?;

                for obj in remote_index.objects {
                    let local_obj = object_path(repo_path, &obj.hash);
                    if local_obj.exists() {
                        continue;
                    }
                    ensure_object_parent_dir(repo_path, &obj.hash)?;
                    let remote_obj_path = Self::remote_object_path(remote_base, &obj.hash).replace('/', "\\");
                    client.download_file(&remote_obj_path, &local_obj).await?;
                    fetched_objects += 1;
                    fetched_size += obj.size;
                }
            }
            Protocol::Smb => {
                let (share, base_path) = Self::parse_smb_share_and_base_path(remote_base)?;
                let client = SmbClient::new(
                    &conn.host,
                    conn.port.unwrap_or(445) as u16,
                    conn.username.as_deref(),
                    conn.password.as_deref(),
                );

                let index_path = Self::remote_object_index_path(&base_path);
                let temp_index = std::env::temp_dir().join(format!(
                    "nanosync-fetch-index-{}.json",
                    crate::utils::hash::generate_uuid()
                ));
                if client.download_file(&share, &index_path, &temp_index).await.is_err() {
                    return Ok((0, 0));
                }
                let content = std::fs::read_to_string(&temp_index)?;
                let _ = std::fs::remove_file(&temp_index);
                let remote_index: RemoteObjectIndex = serde_json::from_str(&content)?;

                for obj in remote_index.objects {
                    let local_obj = object_path(repo_path, &obj.hash);
                    if local_obj.exists() {
                        continue;
                    }
                    ensure_object_parent_dir(repo_path, &obj.hash)?;
                    let remote_obj_path = Self::remote_object_path(&base_path, &obj.hash);
                    if client.download_file(&share, &remote_obj_path, &local_obj).await.is_ok() {
                        fetched_objects += 1;
                        fetched_size += obj.size;
                    }
                }
            }
        }

        Ok((fetched_objects, fetched_size))
    }

    fn calculate_ahead_behind(local_head: Option<&str>, remote_head: Option<&str>) -> AheadBehind {
        match (local_head, remote_head) {
            (Some(l), Some(r)) if !l.is_empty() && !r.is_empty() && l == r => AheadBehind {
                ahead: 0,
                behind: 0,
                ahead_commits: vec![],
                behind_commits: vec![],
            },
            (Some(l), Some(r)) if !l.is_empty() && !r.is_empty() => AheadBehind {
                ahead: 1,
                behind: 1,
                ahead_commits: vec![l.to_string()],
                behind_commits: vec![r.to_string()],
            },
            (Some(l), None) if !l.is_empty() => AheadBehind {
                ahead: 1,
                behind: 0,
                ahead_commits: vec![l.to_string()],
                behind_commits: vec![],
            },
            (None, Some(r)) if !r.is_empty() => AheadBehind {
                ahead: 0,
                behind: 1,
                ahead_commits: vec![],
                behind_commits: vec![r.to_string()],
            },
            _ => AheadBehind {
                ahead: 0,
                behind: 0,
                ahead_commits: vec![],
                behind_commits: vec![],
            },
        }
    }

    async fn apply_remote_repository_state(
        &self,
        repo_db: &RepositoryDatabase,
        state: &RepositoryState,
    ) -> Result<()> {
        for branch in &state.branches {
            if let Some(existing) = repo_db.get_branch(&branch.name).await? {
                if existing.head_commit_id != branch.head_commit_id {
                    repo_db
                        .update_branch_head(&branch.name, &branch.head_commit_id)
                        .await?;
                }
            } else {
                repo_db
                    .create_branch(&branch.name, &branch.head_commit_id, branch.is_default)
                    .await?;
            }
        }

        repo_db.set_default_branch(&state.current_branch).await?;
        Ok(())
    }
}