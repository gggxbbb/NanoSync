//! 自动化运行器

use crate::database::RepositoryDatabase;
use crate::device::DeviceIdentity;
use crate::error::Result;
use crate::models::*;
use crate::repository::RepositoryManager;
use crate::sync::SyncEngine;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{broadcast, RwLock};
use tokio::time::interval;
use tracing::{info, warn};

/// 自动化运行器
pub struct AutomationRunner {
    repo_manager: Arc<RepositoryManager>,
    sync_engine: Arc<SyncEngine>,
    device_identity: DeviceIdentity,
    is_running: Arc<RwLock<bool>>,
    stop_signal: broadcast::Sender<()>,
}

impl AutomationRunner {
    pub fn new(
        repo_manager: Arc<RepositoryManager>,
        sync_engine: Arc<SyncEngine>,
        device_identity: DeviceIdentity,
    ) -> Self {
        let (stop_signal, _) = broadcast::channel(1);
        
        Self {
            repo_manager,
            sync_engine,
            device_identity,
            is_running: Arc::new(RwLock::new(false)),
            stop_signal,
        }
    }

    /// 启动运行器
    pub async fn start(&self) -> Result<()> {
        let mut is_running = self.is_running.write().await;
        if *is_running {
            return Ok(());
        }
        
        *is_running = true;
        drop(is_running);

        info!("自动化运行器已启动");

        let _is_running = self.is_running.clone();
        let repo_manager = self.repo_manager.clone();
        let sync_engine = self.sync_engine.clone();
        let device_identity = self.device_identity.clone();
        let mut stop_rx = self.stop_signal.subscribe();

        tokio::spawn(async move {
            let mut ticker = interval(Duration::from_secs(15));
            
            loop {
                tokio::select! {
                    _ = ticker.tick() => {
                        if let Err(e) = Self::tick(
                            &repo_manager,
                            &sync_engine,
                            &device_identity,
                        ).await {
                            warn!("自动化 tick 失败: {}", e);
                        }
                    }
                    _ = stop_rx.recv() => {
                        info!("自动化运行器已停止");
                        break;
                    }
                }
            }
        });

        Ok(())
    }

    /// 停止运行器
    pub async fn stop(&self) -> Result<()> {
        let mut is_running = self.is_running.write().await;
        *is_running = false;
        
        let _ = self.stop_signal.send(());
        
        info!("自动化运行器停止请求已发送");
        Ok(())
    }

    /// 检查是否运行中
    pub async fn is_running(&self) -> bool {
        *self.is_running.read().await
    }

    /// 周期性 tick
    async fn tick(
        repo_manager: &RepositoryManager,
        sync_engine: &SyncEngine,
        device_identity: &DeviceIdentity,
    ) -> Result<()> {
        // 获取所有仓库
        let repos = repo_manager.list_repositories().await?;
        
        for repo in repos {
            // 获取仓库数据库
            let repo_path = Path::new(&repo.local_path);
            let repo_db = RepositoryDatabase::open(repo_path, repo.id).await?;
            
            // 获取启用的自动化规则
            let rules = repo_db.list_automation_rules().await?;
            
            for rule in rules {
                // 跳过禁用或导入未接管的规则
                if !rule.enabled || rule.is_imported {
                    continue;
                }
                
                // 检查设备指纹
                if rule.owner_device_fingerprint != device_identity.fingerprint {
                    continue;
                }
                
                // 检查是否需要触发
                if Self::should_trigger(&rule, &repo_db).await? {
                    // 执行动作
                    if let Err(e) = Self::execute_action(&rule, repo.id, sync_engine).await {
                        warn!("自动化规则 {} 执行失败: {}", rule.name, e);
                    } else {
                        // 更新最后触发时间
                        repo_db.update_rule_last_triggered(&rule.id).await?;
                    }
                }
            }
        }

        Ok(())
    }

    /// 检查是否应该触发
    async fn should_trigger(rule: &AutomationRule, _repo_db: &RepositoryDatabase) -> Result<bool> {
        match rule.trigger_type {
            TriggerType::TimeBased => {
                // 检查是否到了触发时间
                if let Some(last_triggered) = rule.last_triggered {
                    let elapsed = chrono::Utc::now() - last_triggered;
                    let interval_minutes = rule.debounce_seconds / 60;
                    if elapsed.num_minutes() >= interval_minutes as i64 {
                        return Ok(true);
                    }
                } else {
                    // 从未触发过
                    return Ok(true);
                }
            }
            TriggerType::ChangeBased => {
                // 检查工作区是否有变更：如果曾经触发，基于 debounce 防抖检查
                // 变更检测由外部文件监控触发，这里仅做防抖处理
                if let Some(last_triggered) = rule.last_triggered {
                    let elapsed = chrono::Utc::now() - last_triggered;
                    let debounce_secs = rule.debounce_seconds as i64;
                    if elapsed.num_seconds() < debounce_secs {
                        return Ok(false);
                    }
                }
                // 尝试检测工作区变更
                return Ok(true);
            }
            TriggerType::Schedule => {
                // TODO: cron 表达式解析
            }
        }
        
        Ok(false)
    }

    /// 执行动作
    async fn execute_action(
        rule: &AutomationRule,
        repository_id: i64,
        sync_engine: &SyncEngine,
    ) -> Result<()> {
        info!("执行自动化规则: {} (仓库 {})", rule.name, repository_id);

        match rule.action_type {
            ActionType::Sync => {
                sync_engine.sync(repository_id, None, true).await?;
            }
            ActionType::Fetch => {
                sync_engine.fetch(repository_id, None, true).await?;
            }
            ActionType::Push => {
                sync_engine.push(repository_id, None, false, true).await?;
            }
            ActionType::Pull => {
                sync_engine.pull(repository_id, None, true).await?;
            }
            ActionType::SyncAndPush => {
                sync_engine.sync(repository_id, None, true).await?;
                sync_engine.push(repository_id, None, false, true).await?;
            }
            _ => {
                warn!("暂未实现的动作类型: {:?}", rule.action_type);
            }
        }

        Ok(())
    }

    /// 获取运行器状态
    pub async fn get_status(&self) -> AutomationRunnerStatus {
        AutomationRunnerStatus {
            is_running: *self.is_running.read().await,
            active_rules_count: 0, // TODO: 实际计算
            last_tick: None,
            pending_executions: 0,
            current_executions: 0,
        }
    }
}