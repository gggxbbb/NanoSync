//! 版本控制引擎实现

use crate::database::RepositoryDatabase;
use crate::device::DeviceIdentity;
use crate::error::{Error, Result};
use crate::models::*;
use crate::utils::ignore::IgnoreManager;
use crate::utils::path::*;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tracing::info;
use walkdir::WalkDir;

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

        // 扫描工作目录，检测未暂存的变更
        let unstaged_changes = self.scan_unstaged_changes(&staged).await?;
        let has_staged = !staged.is_empty();
        let has_unstaged = !unstaged_changes.is_empty();

        Ok(WorkingDirectoryStatus {
            is_clean: !has_staged && !has_unstaged,
            staged_changes: staged,
            unstaged_changes,
            conflicts: vec![],
            current_branch,
            head_commit_id,
            ahead: 0,
            behind: 0,
        })
    }

    /// 扫描工作区中未暂存的变更
    async fn scan_unstaged_changes(&self, staged: &[StagingEntry]) -> Result<Vec<FileChange>> {
        // 获取已暂存路径集合（这些路径不计入 unstaged）
        let staged_paths: std::collections::HashSet<&str> =
            staged.iter().map(|e| e.path.as_str()).collect();

        // 获取上次提交的文件状态
        let committed_index = self.repo_db.get_object_index().await?;
        let committed_map: HashMap<String, ObjectIndexEntry> = committed_index
            .into_iter()
            .map(|e| (e.path.clone(), e))
            .collect();

        // 加载忽略规则
        let ignore_manager = IgnoreManager::for_repository(&self.repo_path)
            .unwrap_or_default();

        let mut unstaged = Vec::new();

        // 收集当前工作区文件
        let mut current_files: HashMap<String, String> = HashMap::new(); // path -> hash
        for entry in WalkDir::new(&self.repo_path)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
        {
            let abs_path = entry.path();
            
            // 获取相对路径
            let rel_path = match abs_path.strip_prefix(&self.repo_path) {
                Ok(p) => p.to_string_lossy().replace('\\', "/"),
                Err(_) => continue,
            };

            // 跳过 .nanosync 目录
            if rel_path.starts_with(".nanosync") {
                continue;
            }

            // 跳过被忽略的文件
            if ignore_manager.is_ignored(Path::new(&rel_path)) {
                continue;
            }

            // 跳过已暂存的文件（staged 变更已记录）
            if staged_paths.contains(rel_path.as_str()) {
                continue;
            }

            // 计算文件哈希
            if let Ok(hash) = crate::utils::hash::hash_file_blake3(abs_path) {
                current_files.insert(rel_path, hash);
            }
        }

        // 检测修改和新增
        for (path, hash) in &current_files {
            if let Some(committed) = committed_map.get(path) {
                // 文件已提交，检查是否修改
                if &committed.object_hash != hash {
                    unstaged.push(FileChange {
                        id: crate::utils::hash::generate_uuid(),
                        repository_id: self.repository_id,
                        commit_id: None,
                        path: path.clone(),
                        old_path: None,
                        change_type: ChangeType::Modified,
                        old_hash: Some(committed.object_hash.clone()),
                        new_hash: Some(hash.clone()),
                        old_size: Some(committed.file_size),
                        new_size: std::fs::metadata(self.repo_path.join(path))
                            .ok()
                            .map(|m| m.len() as i64),
                    });
                }
            } else {
                // 新文件
                unstaged.push(FileChange {
                    id: crate::utils::hash::generate_uuid(),
                    repository_id: self.repository_id,
                    commit_id: None,
                    path: path.clone(),
                    old_path: None,
                    change_type: ChangeType::Added,
                    old_hash: None,
                    new_hash: Some(hash.clone()),
                    old_size: None,
                    new_size: std::fs::metadata(self.repo_path.join(path))
                        .ok()
                        .map(|m| m.len() as i64),
                });
            }
        }

        // 检测删除（已提交但当前不存在的文件）
        for (path, committed) in &committed_map {
            if !current_files.contains_key(path) && !staged_paths.contains(path.as_str()) {
                unstaged.push(FileChange {
                    id: crate::utils::hash::generate_uuid(),
                    repository_id: self.repository_id,
                    commit_id: None,
                    path: path.clone(),
                    old_path: None,
                    change_type: ChangeType::Deleted,
                    old_hash: Some(committed.object_hash.clone()),
                    new_hash: None,
                    old_size: Some(committed.file_size),
                    new_size: None,
                });
            }
        }

        Ok(unstaged)
    }

    /// 添加文件到暂存区
    pub async fn add(&self, paths: &[String]) -> Result<()> {
        for path in paths {
            let full_path = self.repo_path.join(path);
            let norm_path = path.replace('\\', "/");

            if !full_path.exists() {
                // 文件不存在，可能是删除操作
                let committed_index = self.repo_db.get_object_index().await?;
                let was_committed = committed_index.iter().any(|e| e.path == norm_path);
                if was_committed {
                    self.repo_db.stage_entry(&norm_path, ChangeType::Deleted, None).await?;
                }
                continue;
            }

            if full_path.is_file() {
                let hash = crate::utils::hash::hash_file_blake3(&full_path)?;
                
                // 确定变更类型
                let committed_index = self.repo_db.get_object_index().await?;
                let change_type = if committed_index.iter().any(|e| e.path == norm_path) {
                    ChangeType::Modified
                } else {
                    ChangeType::Added
                };

                // 存储对象文件到 .nanosync/objects
                self.store_object(&hash, &full_path)?;

                self.repo_db.stage_entry(&norm_path, change_type, Some(&hash)).await?;
            }
        }

        info!("已添加 {} 个文件到暂存区", paths.len());
        Ok(())
    }

    /// 存储对象到 objects 目录
    fn store_object(&self, hash: &str, source_path: &Path) -> Result<()> {
        let objects_dir = objects_dir(&self.repo_path);
        // 使用哈希前2字符作为子目录（类似git）
        let sub_dir = objects_dir.join(&hash[..2]);
        crate::utils::path::ensure_directory(&sub_dir)?;
        let object_path = sub_dir.join(&hash[2..]);
        
        if !object_path.exists() {
            std::fs::copy(source_path, &object_path)?;
        }
        Ok(())
    }

    /// 从 objects 目录还原文件
    fn restore_object(&self, hash: &str, dest_path: &Path) -> Result<()> {
        let objects_dir = objects_dir(&self.repo_path);
        let object_path = objects_dir.join(&hash[..2]).join(&hash[2..]);
        
        if !object_path.exists() {
            return Err(Error::VersionControl(format!("对象不存在: {}", hash)));
        }
        
        if let Some(parent) = dest_path.parent() {
            crate::utils::path::ensure_directory(parent)?;
        }
        std::fs::copy(&object_path, dest_path)?;
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

        // 计算树哈希：基于暂存条目的路径+哈希
        let tree_content: String = staged.iter()
            .map(|e| format!("{}:{}", e.path, e.object_id.as_deref().unwrap_or("")))
            .collect::<Vec<_>>()
            .join("\n");
        let tree_root = crate::utils::hash::hash_bytes_blake3(tree_content.as_bytes());

        let commit = Commit {
            id: commit_id.clone(),
            repository_id: self.repository_id,
            branch_name: default_branch.name.clone(),
            parent_ids: if default_branch.head_commit_id.is_empty() {
                vec![]
            } else {
                vec![default_branch.head_commit_id.clone()]
            },
            message: message.to_string(),
            author: author.unwrap_or(&self.device_identity.username).to_string(),
            author_email: author_email.map(|s| s.to_string()),
            timestamp: now,
            tree_root,
            created_at: now,
        };

        self.repo_db.add_commit(&commit).await?;
        self.repo_db.update_branch_head(&default_branch.name, &commit_id).await?;

        // 更新对象索引
        let mut index_updates: Vec<ObjectIndexEntry> = Vec::new();
        let mut deleted_paths: Vec<String> = Vec::new();

        for entry in &staged {
            match entry.change_type {
                ChangeType::Deleted => {
                    deleted_paths.push(entry.path.clone());
                }
                _ => {
                    let file_size = entry.object_id.as_ref()
                        .and_then(|hash| {
                            let sub = objects_dir(&self.repo_path).join(&hash[..2]).join(&hash[2..]);
                            std::fs::metadata(&sub).ok().map(|m| m.len() as i64)
                        })
                        .unwrap_or(0);
                    
                    index_updates.push(ObjectIndexEntry {
                        path: entry.path.clone(),
                        object_hash: entry.object_id.clone().unwrap_or_default(),
                        file_size,
                        commit_id: commit_id.clone(),
                    });
                }
            }
        }

        // 更新对象索引
        self.repo_db.update_object_index(&index_updates).await?;
        for path in &deleted_paths {
            self.repo_db.remove_from_object_index(path).await?;
        }

        // 清空暂存区
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
        if staged {
            // 显示暂存区变更与上一次提交的差异
            let staged_entries = self.repo_db.list_staged_entries().await?;
            let committed_index = self.repo_db.get_object_index().await?;
            let committed_map: HashMap<String, &ObjectIndexEntry> = committed_index.iter()
                .filter(|e| path.map_or(true, |p| e.path == p))
                .map(|e| (e.path.clone(), e))
                .collect();

            let mut results = Vec::new();

            for entry in &staged_entries {
                if let Some(p) = path {
                    if entry.path != p {
                        continue;
                    }
                }

                let old_content = if let Some(committed) = committed_map.get(&entry.path) {
                    self.read_object_content(&committed.object_hash).unwrap_or_default()
                } else {
                    String::new()
                };

                let new_content = if let Some(hash) = &entry.object_id {
                    self.read_object_content(hash).unwrap_or_default()
                } else {
                    String::new()
                };

                if let Some(diff) = compute_diff(&entry.path, &old_content, &new_content) {
                    results.push(diff);
                }
            }

            Ok(results)
        } else if let Some(commit) = commit_id {
            // 显示指定提交的变更
            let _ = commit;
            Ok(vec![])
        } else {
            // 显示工作区未暂存的变更
            let status = self.status().await?;
            let mut results = Vec::new();

            for change in &status.unstaged_changes {
                if let Some(p) = path {
                    if change.path != p {
                        continue;
                    }
                }

                let old_content = if let Some(hash) = &change.old_hash {
                    self.read_object_content(hash).unwrap_or_default()
                } else {
                    String::new()
                };

                let new_content = if change.change_type != ChangeType::Deleted {
                    std::fs::read_to_string(self.repo_path.join(&change.path))
                        .unwrap_or_default()
                } else {
                    String::new()
                };

                if let Some(diff) = compute_diff(&change.path, &old_content, &new_content) {
                    results.push(diff);
                }
            }

            Ok(results)
        }
    }

    /// 读取对象内容
    fn read_object_content(&self, hash: &str) -> Option<String> {
        if hash.len() < 3 {
            return None;
        }
        let object_path = objects_dir(&self.repo_path)
            .join(&hash[..2])
            .join(&hash[2..]);
        std::fs::read_to_string(&object_path).ok()
    }

    /// 重置
    pub async fn reset(&self, reset_type: ResetType, _target: Option<&str>, paths: Option<&[String]>) -> Result<()> {
        match reset_type {
            ResetType::Soft => {
                // 保留暂存区和工作区，不需要操作
            }
            ResetType::Mixed => {
                // 重置暂存区，保留工作区
                if let Some(paths) = paths {
                    for path in paths {
                        self.repo_db.unstage_entry(path).await?;
                    }
                } else {
                    self.repo_db.clear_staging().await?;
                }
            }
            ResetType::Hard => {
                // 重置暂存区和工作区：从对象索引还原文件
                self.repo_db.clear_staging().await?;
                
                // 从对象索引还原文件
                let index = self.repo_db.get_object_index().await?;
                let paths_to_restore: Vec<&ObjectIndexEntry> = if let Some(paths) = paths {
                    index.iter().filter(|e| paths.contains(&e.path)).collect()
                } else {
                    index.iter().collect()
                };

                for entry in paths_to_restore {
                    let dest = self.repo_path.join(&entry.path);
                    if !entry.object_hash.is_empty() {
                        let _ = self.restore_object(&entry.object_hash, &dest);
                    }
                }
            }
        }

        info!("重置完成: {:?}", reset_type);
        Ok(())
    }

    /// 创建分支
    pub async fn create_branch(&self, name: &str, base_commit_id: Option<&str>, _checkout: bool) -> Result<String> {
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
        let _branch = self.repo_db.get_branch(name).await?
            .ok_or(Error::BranchNotFound(name.to_string()))?;

        self.repo_db.set_default_branch(name).await?;
        
        info!("切换到分支: {}", name);
        Ok(())
    }

    /// 删除分支
    pub async fn delete_branch(&self, name: &str, _force: bool) -> Result<()> {
        let branch = self.repo_db.get_branch(name).await?
            .ok_or(Error::BranchNotFound(name.to_string()))?;

        if branch.is_default {
            return Err(Error::VersionControl("不能删除默认分支".to_string()));
        }

        sqlx_delete_branch(&self.repo_db, name).await?;
        info!("分支删除成功: {}", name);
        Ok(())
    }

    /// Stash 操作
    pub async fn stash(&self, message: Option<&str>, _include_untracked: bool) -> Result<String> {
        let status = self.status().await?;
        
        if status.is_clean {
            return Err(Error::VersionControl("工作区是干净的".to_string()));
        }

        let stash_id = crate::utils::hash::generate_uuid();
        let default_branch = self.repo_db.get_default_branch().await?
            .ok_or(Error::VersionControl("没有默认分支".to_string()))?;

        // 创建 stash 记录
        let stash = Stash {
            id: stash_id.clone(),
            repository_id: self.repository_id,
            name: None,
            message: message.map(|s| s.to_string()),
            commit_id: default_branch.head_commit_id.clone(),
            branch_name: default_branch.name.clone(),
            created_at: chrono::Utc::now(),
        };
        self.repo_db.add_stash(&stash).await?;

        // 保存已暂存的文件到 stash_entries
        for entry in &status.staged_changes {
            if let Some(hash) = &entry.object_id {
                let stash_entry = StashEntry {
                    id: crate::utils::hash::generate_uuid(),
                    stash_id: stash_id.clone(),
                    path: entry.path.clone(),
                    object_id: hash.clone(),
                    change_type: entry.change_type,
                };
                self.repo_db.add_stash_entry(&stash_entry).await?;
            }
        }

        // 清空暂存区
        self.repo_db.clear_staging().await?;

        info!("Stash 创建成功: {}", stash_id);
        Ok(stash_id)
    }

    /// Stash pop
    pub async fn stash_pop(&self, stash_id: Option<&str>) -> Result<()> {
        let stashes = self.repo_db.list_stashes().await?;
        let stash = if let Some(id) = stash_id {
            stashes.into_iter().find(|s| s.id == id)
        } else {
            stashes.into_iter().next()
        };

        let stash = stash.ok_or(Error::VersionControl("没有找到 stash".to_string()))?;

        // 恢复 stash 条目到暂存区
        let entries = self.repo_db.list_stash_entries(&stash.id).await?;
        for entry in entries {
            self.repo_db.stage_entry(&entry.path, entry.change_type, Some(&entry.object_id)).await?;
        }

        // 删除 stash
        self.repo_db.delete_stash(&stash.id).await?;
        
        info!("Stash pop 完成: {}", stash.id);
        Ok(())
    }

    /// 列出 stash
    pub async fn stash_list(&self) -> Result<Vec<Stash>> {
        self.repo_db.list_stashes().await
    }

    /// 获取所有分支
    pub async fn list_branches(&self) -> Result<Vec<Branch>> {
        self.repo_db.list_branches().await
    }
}

/// 简单的行级 diff 算法
fn compute_diff(path: &str, old_content: &str, new_content: &str) -> Option<DiffResult> {
    let is_binary = old_content.contains('\0') || new_content.contains('\0');

    if is_binary {
        return Some(DiffResult {
            path: path.to_string(),
            hunks: vec![],
            is_binary: true,
        });
    }

    let old_lines: Vec<&str> = old_content.lines().collect();
    let new_lines: Vec<&str> = new_content.lines().collect();

    if old_lines == new_lines {
        return None;
    }

    let mut hunk_lines: Vec<DiffLine> = Vec::new();
    let mut old_line = 0u32;
    let mut new_line = 0u32;
    let mut i = 0usize;
    let mut j = 0usize;

    while i < old_lines.len() || j < new_lines.len() {
        if i < old_lines.len() && j < new_lines.len() && old_lines[i] == new_lines[j] {
            // Same line
            hunk_lines.push(DiffLine {
                line_type: DiffLineType::Context,
                content: old_lines[i].to_string(),
                old_line: Some(old_line + 1),
                new_line: Some(new_line + 1),
            });
            old_line += 1;
            new_line += 1;
            i += 1;
            j += 1;
        } else {
            // Different: output old as delete, new as add
            if i < old_lines.len() {
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Delete,
                    content: old_lines[i].to_string(),
                    old_line: Some(old_line + 1),
                    new_line: None,
                });
                old_line += 1;
                i += 1;
            }
            if j < new_lines.len() {
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Add,
                    content: new_lines[j].to_string(),
                    old_line: None,
                    new_line: Some(new_line + 1),
                });
                new_line += 1;
                j += 1;
            }
        }
    }

    if hunk_lines.is_empty() {
        return None;
    }

    let hunk = DiffHunk {
        old_start: 1,
        old_lines: old_lines.len() as u32,
        new_start: 1,
        new_lines: new_lines.len() as u32,
        lines: hunk_lines,
    };

    Some(DiffResult {
        path: path.to_string(),
        hunks: vec![hunk],
        is_binary: false,
    })
}

/// 辅助函数：删除分支
async fn sqlx_delete_branch(repo_db: &RepositoryDatabase, name: &str) -> Result<()> {
    // This is done through the pool which is private. 
    // We'll call it as part of the future update_automation_rule update
    // For now, create branch deletion through the existing API
    // Actually we need to expose delete_branch from RepositoryDatabase
    repo_db.delete_branch(name).await
}
