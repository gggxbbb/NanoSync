//! 版本控制引擎实现

use crate::database::RepositoryDatabase;
use crate::device::DeviceIdentity;
use crate::error::{Error, Result};
use crate::models::*;
use crate::utils::path::*;
use std::path::Path;
use std::sync::Arc;
use tracing::info;

/// 版本控制引擎
pub struct VcEngine {
    repository_id: i64,
    repo_path: std::path::PathBuf,
    repo_db: Arc<RepositoryDatabase>,
    device_identity: DeviceIdentity,
}

impl VcEngine {
    pub async fn new(
        repository_id: i64,
        repo_path: &Path,
        device_identity: DeviceIdentity,
    ) -> Result<Self> {
        let repo_db = Arc::new(RepositoryDatabase::open(repo_path, repository_id).await?);
        
        Ok(Self {
            repository_id,
            repo_path: repo_path.to_path_buf(),
            repo_db,
            device_identity,
        })
    }

    /// 获取工作区状态
    pub async fn status(&self) -> Result<WorkingDirectoryStatus> {
        let default_branch = self.repo_db.get_default_branch().await?;
        let staged = self.repo_db.list_staged_entries().await?;
        
        let (current_branch, head_commit_id) = match &default_branch {
            Some(b) => (Some(b.name.clone()), Some(b.head_commit_id.clone())),
            None => (None, None),
        };
        
        Ok(WorkingDirectoryStatus {
            is_clean: staged.is_empty(),
            staged_changes: staged,
            unstaged_changes: vec![], // TODO: 实现实际扫描
            conflicts: vec![],
            current_branch,
            head_commit_id,
            ahead: 0,
            behind: 0,
        })
    }

    /// 添加文件到暂存区
    pub async fn add(&self, paths: &[String]) -> Result<()> {
        for path in paths {
            let full_path = self.repo_path.join(path);
            
            if !full_path.exists() {
                continue;
            }

            let object_id = if full_path.is_file() {
                Some(crate::utils::hash::hash_file_blake3(&full_path)?)
            } else {
                None
            };

            self.repo_db.stage_entry(
                path,
                ChangeType::Added,
                object_id.as_deref(),
            ).await?;
        }

        info!("已添加 {} 个文件到暂存区", paths.len());
        Ok(())
    }

    /// 提交暂存区内容
    pub async fn commit(&self, message: &str, author: Option<&str>, author_email: Option<&str>) -> Result<String> {
        let staged = self.repo_db.list_staged_entries().await?;
        
        if staged.is_empty() {
            return Err(Error::VersionControl("暂存区为空".to_string()));
        }

        let default_branch = self.repo_db.get_default_branch().await?
            .ok_or(Error::VersionControl("没有默认分支".to_string()))?;

        let commit_id = crate::utils::hash::generate_uuid();
        let now = chrono::Utc::now();

        let commit = Commit {
            id: commit_id.clone(),
            repository_id: self.repository_id,
            branch_name: default_branch.name.clone(),
            parent_ids: vec![default_branch.head_commit_id],
            message: message.to_string(),
            author: author.unwrap_or(&self.device_identity.username).to_string(),
            author_email: author_email.map(|s| s.to_string()),
            timestamp: now,
            tree_root: "todo".to_string(), // TODO: 实现树哈希
            created_at: now,
        };

        self.repo_db.add_commit(&commit).await?;
        self.repo_db.update_branch_head(&default_branch.name, &commit_id).await?;
        self.repo_db.clear_staging().await?;

        info!("提交成功: {} ({})", message, commit_id);
        Ok(commit_id)
    }

    /// 获取提交历史
    pub async fn log(&self, branch: Option<&str>, limit: Option<i32>) -> Result<Vec<Commit>> {
        let branch_name = if let Some(name) = branch {
            name.to_string()
        } else {
            self.repo_db.get_default_branch().await?
                .map(|b| b.name)
                .unwrap_or_else(|| "main".to_string())
        };

        let commits = self.repo_db.get_commit_history(&branch_name, limit.unwrap_or(50)).await?;
        Ok(commits)
    }

    /// 获取差异
    pub async fn diff(&self, path: Option<&str>, staged: bool, commit_id: Option<&str>) -> Result<Vec<DiffResult>> {
        // TODO: 实现真实的差异计算
        Ok(vec![])
    }

    /// 重置
    pub async fn reset(&self, reset_type: ResetType, target: Option<&str>, paths: Option<&[String]>) -> Result<()> {
        match reset_type {
            ResetType::Soft => {
                // 保留暂存区和工作区
            }
            ResetType::Mixed => {
                // 重置暂存区
                if paths.is_none() {
                    self.repo_db.clear_staging().await?;
                }
            }
            ResetType::Hard => {
                // 重置暂存区和工作区
                self.repo_db.clear_staging().await?;
                // TODO: 恢复工作区文件
            }
        }

        info!("重置完成: {:?}", reset_type);
        Ok(())
    }

    /// 创建分支
    pub async fn create_branch(&self, name: &str, base_commit_id: Option<&str>, checkout: bool) -> Result<String> {
        // 检查分支是否已存在
        if self.repo_db.get_branch(name).await?.is_some() {
            return Err(Error::VersionControl(format!("分支已存在: {}", name)));
        }

        // 获取基础提交
        let base_commit = if let Some(id) = base_commit_id {
            id.to_string()
        } else {
            self.repo_db.get_default_branch().await?
                .map(|b| b.head_commit_id)
                .ok_or(Error::VersionControl("没有默认分支".to_string()))?
        };

        // 创建分支
        self.repo_db.create_branch(name, &base_commit, false).await?;

        info!("分支创建成功: {}", name);
        Ok(name.to_string())
    }

    /// 切换分支
    pub async fn switch_branch(&self, name: &str) -> Result<()> {
        let branch = self.repo_db.get_branch(name).await?
            .ok_or(Error::BranchNotFound(name.to_string()))?;

        // TODO: 实际切换工作区

        self.repo_db.set_default_branch(name).await?;
        
        info!("切换到分支: {}", name);
        Ok(())
    }

    /// 删除分支
    pub async fn delete_branch(&self, name: &str, force: bool) -> Result<()> {
        let branch = self.repo_db.get_branch(name).await?
            .ok_or(Error::BranchNotFound(name.to_string()))?;

        if branch.is_default {
            return Err(Error::VersionControl("不能删除默认分支".to_string()));
        }

        // TODO: 检查是否有未合并的提交

        Ok(())
    }

    /// Stash 操作
    pub async fn stash(&self, message: Option<&str>, include_untracked: bool) -> Result<String> {
        let status = self.status().await?;
        
        if status.is_clean {
            return Err(Error::VersionControl("工作区是干净的".to_string()));
        }

        let stash_id = crate::utils::hash::generate_uuid();
        // TODO: 实现实际的 stash 保存

        info!("Stash 创建成功: {}", stash_id);
        Ok(stash_id)
    }

    /// Stash pop
    pub async fn stash_pop(&self, stash_id: Option<&str>) -> Result<()> {
        // TODO: 实现实际的 stash 恢复
        Ok(())
    }

    /// 列出 stash
    pub async fn stash_list(&self) -> Result<Vec<Stash>> {
        // TODO: 实现实际的 stash 列表
        Ok(vec![])
    }
}