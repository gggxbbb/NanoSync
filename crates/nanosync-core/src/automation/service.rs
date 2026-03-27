//! 自动化规则服务

use crate::database::RepositoryDatabase;
use crate::device::DeviceIdentity;
use crate::error::{Error, Result};
use crate::models::*;
use std::path::Path;
use tracing::info;

/// 自动化规则服务
pub struct AutomationService;

impl AutomationService {
    /// 创建自动化规则
    pub async fn create_rule(
        repo_db: &RepositoryDatabase,
        request: &CreateAutomationRuleRequest,
        device_identity: &DeviceIdentity,
    ) -> Result<AutomationRule> {
        let now = chrono::Utc::now();
        let id = crate::utils::hash::generate_uuid();

        let rule = AutomationRule {
            id,
            repository_id: request.repository_id,
            name: request.name.clone(),
            description: request.description.clone(),
            trigger_type: request.trigger_type,
            action_type: request.action_type,
            enabled: true,
            owner_device_fingerprint: device_identity.fingerprint.clone(),
            is_imported: false,
            last_triggered: None,
            retry_count: request.retry_count.unwrap_or(0),
            retry_delay_seconds: request.retry_delay_seconds.unwrap_or(60),
            debounce_seconds: request.debounce_seconds.unwrap_or(0),
            created_at: now,
            updated_at: now,
        };

        repo_db.add_automation_rule(&rule).await?;
        
        info!("自动化规则创建成功: {}", rule.name);
        Ok(rule)
    }

    /// 更新自动化规则
    pub async fn update_rule(
        repo_db: &RepositoryDatabase,
        request: &UpdateAutomationRuleRequest,
    ) -> Result<AutomationRule> {
        // 获取现有规则
        let rules = repo_db.list_automation_rules().await?;
        let existing = rules.iter()
            .find(|r| r.id == request.rule_id)
            .ok_or(Error::AutomationRuleNotFound(0))?
            .clone();

        let mut rule = existing.clone();
        
        if let Some(name) = &request.name {
            rule.name = name.clone();
        }
        if let Some(description) = &request.description {
            rule.description = Some(description.clone());
        }
        if let Some(trigger_type) = request.trigger_type {
            rule.trigger_type = trigger_type;
        }
        if let Some(action_type) = request.action_type {
            rule.action_type = action_type;
        }
        if let Some(enabled) = request.enabled {
            rule.enabled = enabled;
        }
        if let Some(retry_count) = request.retry_count {
            rule.retry_count = retry_count;
        }
        if let Some(retry_delay_seconds) = request.retry_delay_seconds {
            rule.retry_delay_seconds = retry_delay_seconds;
        }
        if let Some(debounce_seconds) = request.debounce_seconds {
            rule.debounce_seconds = debounce_seconds;
        }

        rule.updated_at = chrono::Utc::now();

        repo_db.update_automation_rule(&rule).await?;
        
        info!("自动化规则更新成功: {}", rule.name);
        Ok(rule)
    }

    /// 删除自动化规则
    pub async fn delete_rule(repo_db: &RepositoryDatabase, rule_id: &str) -> Result<()> {
        repo_db.delete_automation_rule(rule_id).await?;
        
        info!("自动化规则删除成功: {}", rule_id);
        Ok(())
    }

    /// 切换规则启用状态
    pub async fn toggle_rule(
        repo_db: &RepositoryDatabase,
        rule_id: &str,
        enabled: bool,
    ) -> Result<()> {
        let rules = repo_db.list_automation_rules().await?;
        let existing = rules.iter()
            .find(|r| r.id == rule_id)
            .ok_or(Error::AutomationRuleNotFound(0))?;

        let mut rule = existing.clone();
        rule.enabled = enabled;
        rule.updated_at = chrono::Utc::now();

        repo_db.update_automation_rule(&rule).await?;
        
        info!("自动化规则 {} 状态切换为: {}", rule.name, enabled);
        Ok(())
    }

    /// 接管规则（将规则的设备指纹更新为当前设备）
    pub async fn takeover_rule(
        repo_db: &RepositoryDatabase,
        rule_id: &str,
        device_identity: &DeviceIdentity,
    ) -> Result<AutomationRule> {
        let rules = repo_db.list_automation_rules().await?;
        let existing = rules.iter()
            .find(|r| r.id == rule_id)
            .ok_or(Error::AutomationRuleNotFound(0))?
            .clone();

        let mut rule = existing.clone();
        rule.owner_device_fingerprint = device_identity.fingerprint.clone();
        rule.is_imported = false;
        rule.updated_at = chrono::Utc::now();

        repo_db.update_automation_rule(&rule).await?;
        
        info!("自动化规则接管成功: {}", rule.name);
        Ok(rule)
    }

    /// 列出仓库的自动化规则
    pub async fn list_rules(repo_db: &RepositoryDatabase) -> Result<Vec<AutomationRule>> {
        repo_db.list_automation_rules().await
    }

    /// 获取单个规则
    pub async fn get_rule(repo_db: &RepositoryDatabase, rule_id: &str) -> Result<Option<AutomationRule>> {
        let rules = repo_db.list_automation_rules().await?;
        Ok(rules.into_iter().find(|r| r.id == rule_id))
    }
}