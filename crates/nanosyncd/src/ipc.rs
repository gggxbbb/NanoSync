//! IPC 服务实现

use nanosync_core::database::DatabaseManager;
use nanosync_core::device::DeviceIdentity;
use nanosync_core::models::*;
use nanosync_core::repository::RepositoryManager;
use nanosync_core::remote::RemoteConnectionManager;
use nanosync_core::sync::SyncEngine;
use nanosync_core::automation::AutomationRunner;
use nanosync_core::logging::LogService;
use nanosync_protocol::*;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::broadcast;
use tracing::{error, info, warn};

// 平台特定导入
#[cfg(windows)]
use tokio::net::windows::named_pipe::{NamedPipeServer, ServerOptions};

#[cfg(not(windows))]
use tokio::net::{UnixListener, UnixStream};

/// 默认管道名称 (Windows)
#[cfg(windows)]
const DEFAULT_PIPE_NAME: &str = r"\\.\pipe\nanosyncd";

/// 默认 socket 路径 (Unix)
#[cfg(not(windows))]
const DEFAULT_SOCKET_PATH: &str = "/tmp/nanosyncd.sock";

/// IPC 服务器
pub struct IpcServer {
    db: Arc<DatabaseManager>,
    repo_manager: Arc<RepositoryManager>,
    remote_manager: Arc<RemoteConnectionManager>,
    sync_engine: Arc<SyncEngine>,
    automation_runner: Arc<AutomationRunner>,
    log_service: Arc<LogService>,
    device_identity: DeviceIdentity,
    start_time: Instant,
    stop_tx: broadcast::Sender<()>,
}

impl IpcServer {
    pub fn new(
        db: Arc<DatabaseManager>,
        repo_manager: Arc<RepositoryManager>,
        remote_manager: Arc<RemoteConnectionManager>,
        sync_engine: Arc<SyncEngine>,
        automation_runner: Arc<AutomationRunner>,
        log_service: Arc<LogService>,
        device_identity: DeviceIdentity,
    ) -> Self {
        let (stop_tx, _) = broadcast::channel(1);
        
        Self {
            db,
            repo_manager,
            remote_manager,
            sync_engine,
            automation_runner,
            log_service,
            device_identity,
            start_time: Instant::now(),
            stop_tx,
        }
    }

    /// 运行 IPC 服务
    pub async fn run(&self) -> anyhow::Result<()> {
        #[cfg(windows)]
        {
            self.run_windows().await
        }
        
        #[cfg(not(windows))]
        {
            self.run_unix().await
        }
    }

    #[cfg(windows)]
    async fn run_windows(&self) -> anyhow::Result<()> {
        info!("Windows 命名管道服务启动: {}", DEFAULT_PIPE_NAME);

        let mut stop_rx = self.stop_tx.subscribe();
        
        loop {
            // 创建新的命名管道实例
            let server = ServerOptions::new()
                .first_pipe_instance(false)
                .create(DEFAULT_PIPE_NAME)?;
            
            tokio::select! {
                _ = stop_rx.recv() => {
                    info!("收到停止信号");
                    break;
                }
                result = server.connect() => {
                    match result {
                        Ok(()) => {
                            let handler = ClientHandler {
                                db: self.db.clone(),
                                repo_manager: self.repo_manager.clone(),
                                remote_manager: self.remote_manager.clone(),
                                sync_engine: self.sync_engine.clone(),
                                automation_runner: self.automation_runner.clone(),
                                log_service: self.log_service.clone(),
                                device_identity: self.device_identity.clone(),
                                start_time: self.start_time,
                                stop_tx: self.stop_tx.clone(),
                            };
                            tokio::spawn(async move {
                                if let Err(e) = handler.handle_windows_client(server).await {
                                    error!("客户端处理错误: {}", e);
                                }
                            });
                        }
                        Err(e) => {
                            error!("接受连接错误: {}", e);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    #[cfg(not(windows))]
    async fn run_unix(&self) -> anyhow::Result<()> {
        // 删除可能存在的旧 socket 文件
        let _ = std::fs::remove_file(DEFAULT_SOCKET_PATH);
        
        let listener = UnixListener::bind(DEFAULT_SOCKET_PATH)?;
        info!("Unix socket 服务启动: {}", DEFAULT_SOCKET_PATH);

        let mut stop_rx = self.stop_tx.subscribe();
        
        loop {
            tokio::select! {
                _ = stop_rx.recv() => {
                    info!("收到停止信号");
                    break;
                }
                result = listener.accept() => {
                    match result {
                        Ok((stream, _)) => {
                            let handler = ClientHandler {
                                db: self.db.clone(),
                                repo_manager: self.repo_manager.clone(),
                                remote_manager: self.remote_manager.clone(),
                                sync_engine: self.sync_engine.clone(),
                                automation_runner: self.automation_runner.clone(),
                                log_service: self.log_service.clone(),
                                device_identity: self.device_identity.clone(),
                                start_time: self.start_time,
                                stop_tx: self.stop_tx.clone(),
                            };
                            tokio::spawn(async move {
                                if let Err(e) = handler.handle_unix_client(stream).await {
                                    error!("客户端处理错误: {}", e);
                                }
                            });
                        }
                        Err(e) => {
                            error!("接受连接错误: {}", e);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// 获取服务状态
    pub fn get_status(&self) -> ServiceStatus {
        ServiceStatus {
            version: env!("CARGO_PKG_VERSION").to_string(),
            uptime_seconds: self.start_time.elapsed().as_secs(),
            repositories_count: 0, // TODO: 实际获取
            active_syncs: 0,
            automation_running: false,
        }
    }
}

/// 客户端处理
struct ClientHandler {
    db: Arc<DatabaseManager>,
    repo_manager: Arc<RepositoryManager>,
    remote_manager: Arc<RemoteConnectionManager>,
    sync_engine: Arc<SyncEngine>,
    automation_runner: Arc<AutomationRunner>,
    log_service: Arc<LogService>,
    device_identity: DeviceIdentity,
    start_time: Instant,
    stop_tx: broadcast::Sender<()>,
}

impl ClientHandler {
    #[cfg(windows)]
    async fn handle_windows_client(&self, mut stream: NamedPipeServer) -> anyhow::Result<()> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        
        let mut buffer = vec![0u8; 65536];
        
        loop {
            let n = stream.read(&mut buffer).await?;
            if n == 0 {
                break;
            }

            let message = codec::MessageCodec::decode(&buffer[..n])?;
            let response = self.handle_message(&message).await;
            let encoded = codec::MessageCodec::encode(&response)?;
            
            stream.write_all(&encoded).await?;
        }

        Ok(())
    }

    #[cfg(not(windows))]
    async fn handle_unix_client(&self, mut stream: UnixStream) -> anyhow::Result<()> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        
        let mut buffer = vec![0u8; 65536];
        
        loop {
            let n = stream.read(&mut buffer).await?;
            if n == 0 {
                break;
            }

            let message = codec::MessageCodec::decode(&buffer[..n])?;
            let response = self.handle_message(&message).await;
            let encoded = codec::MessageCodec::encode(&response)?;
            
            stream.write_all(&encoded).await?;
        }

        Ok(())
    }

    async fn handle_message(&self, message: &IpcMessage) -> IpcMessage {
        match message.kind {
            MessageKind::Request => {
                match self.handle_command(message).await {
                    Ok(response) => IpcMessage::response(&message.id, response),
                    Err(e) => IpcMessage::error(&message.id, &e.to_string()),
                }
            }
            MessageKind::Event => {
                // TODO: 处理事件订阅
                IpcMessage::error(&message.id, "不支持的请求类型")
            }
            _ => IpcMessage::error(&message.id, "无效的请求类型"),
        }
    }

    async fn handle_command(&self, message: &IpcMessage) -> anyhow::Result<serde_json::Value> {
        let command: command::Command = message.parse()?;
        
        match command {
            command::Command::Ping(ping) => {
                Ok(serde_json::to_value(command::PongResponse {
                    message: ping.message.unwrap_or_else(|| "pong".to_string()),
                    timestamp: chrono::Utc::now().to_rfc3339(),
                })?)
            }
            command::Command::GetStatus => {
                let repos = self.repo_manager.list_repositories().await.unwrap_or_default();
                let automation_running = self.automation_runner.is_running().await;
                let status = ServiceStatus {
                    version: env!("CARGO_PKG_VERSION").to_string(),
                    uptime_seconds: self.start_time.elapsed().as_secs(),
                    repositories_count: repos.len() as i32,
                    active_syncs: 0,
                    automation_running,
                };
                Ok(serde_json::to_value(status)?)
            }
            command::Command::Shutdown => {
                let _ = self.stop_tx.send(());
                Ok(serde_json::json!({"success": true}))
            }
            
            // ===== 仓库管理 =====
            command::Command::ListRepositories => {
                let repos = self.repo_manager.list_repositories().await?;
                Ok(serde_json::to_value(repos)?)
            }
            command::Command::GetRepository(cmd) => {
                let repo = self.repo_manager.get_repository(cmd.id).await?;
                Ok(serde_json::to_value(repo)?)
            }
            command::Command::RegisterRepository(cmd) => {
                let repo = self.db.register_repository(&cmd.name, &cmd.local_path).await?;
                Ok(serde_json::to_value(repo)?)
            }
            command::Command::UnregisterRepository(cmd) => {
                self.repo_manager.unregister_repository(cmd.id, false).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::ImportRepository(cmd) => {
                let repo = self.repo_manager.import_repository(&cmd.options).await?;
                Ok(serde_json::to_value(repo)?)
            }
            command::Command::CloneRepository(_cmd) => {
                // 目前 clone 功能依赖实际的远端文件传输，返回提示信息
                warn!("CloneRepository 命令尚未完整实现");
                Ok(serde_json::json!({"error": "克隆功能需要远端连接支持，暂未实现"}))
            }
            command::Command::MigrateRepository(cmd) => {
                self.repo_manager.migrate_repository(cmd.repository_id, &cmd.new_path).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::DeleteRepository(cmd) => {
                self.repo_manager.unregister_repository(cmd.repository_id, cmd.delete_nanosync_folder).await?;
                Ok(serde_json::json!({"success": true}))
            }
            
            // ===== 远程连接管理 =====
            command::Command::ListRemoteConnections => {
                let conns = self.remote_manager.list_connections().await?;
                Ok(serde_json::to_value(conns)?)
            }
            command::Command::GetRemoteConnection(cmd) => {
                let conn = self.remote_manager.get_connection(cmd.id).await?;
                Ok(serde_json::to_value(conn)?)
            }
            command::Command::CreateRemoteConnection(cmd) => {
                let conn = self.remote_manager.create_connection(&cmd.request).await?;
                Ok(serde_json::to_value(conn)?)
            }
            command::Command::UpdateRemoteConnection(cmd) => {
                self.remote_manager.update_connection(&cmd.request).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::DeleteRemoteConnection(cmd) => {
                self.remote_manager.delete_connection(cmd.id).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::TestRemoteConnection(cmd) => {
                let result = self.remote_manager.test_connection(cmd.id, cmd.test_path.as_deref()).await?;
                Ok(serde_json::to_value(result)?)
            }
            
            // ===== 仓库远端绑定 =====
            command::Command::ListRepositoryRemotes(cmd) => {
                let repo_db = self.get_repo_db(cmd.repository_id).await?;
                let remotes = repo_db.list_repository_remotes().await?;
                Ok(serde_json::to_value(remotes)?)
            }
            command::Command::BindRemote(cmd) => {
                let repo_db = self.get_repo_db(cmd.request.repository_id).await?;
                let remote = RepositoryRemote {
                    remote_name: cmd.request.remote_name,
                    connection_id: cmd.request.connection_id,
                    remote_path: cmd.request.remote_path,
                    is_default: cmd.request.is_default,
                    last_sync: None,
                    last_fetch: None,
                    created_at: chrono::Utc::now(),
                };
                repo_db.add_repository_remote(&remote).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::UnbindRemote(cmd) => {
                let repo_db = self.get_repo_db(cmd.repository_id).await?;
                repo_db.delete_repository_remote(&cmd.remote_name).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::SetDefaultRemote(cmd) => {
                let repo_db = self.get_repo_db(cmd.repository_id).await?;
                repo_db.set_default_remote(&cmd.remote_name).await?;
                Ok(serde_json::json!({"success": true}))
            }
            
            // ===== 同步操作 =====
            command::Command::Fetch(cmd) => {
                let result = self.sync_engine.fetch(cmd.repository_id, cmd.remote_name.as_deref(), cmd.record_log).await?;
                Ok(serde_json::to_value(result)?)
            }
            command::Command::Push(cmd) => {
                let result = self.sync_engine.push(cmd.repository_id, cmd.remote_name.as_deref(), cmd.force, cmd.record_log).await?;
                Ok(serde_json::to_value(result)?)
            }
            command::Command::Pull(cmd) => {
                let result = self.sync_engine.pull(cmd.repository_id, cmd.remote_name.as_deref(), cmd.record_log).await?;
                Ok(serde_json::to_value(result)?)
            }
            command::Command::Sync(cmd) => {
                let result = self.sync_engine.sync(cmd.repository_id, cmd.remote_name.as_deref(), cmd.record_log).await?;
                Ok(serde_json::to_value(result)?)
            }
            command::Command::GetSyncStatus(cmd) => {
                let result = self.sync_engine.get_sync_status(cmd.repository_id).await?;
                Ok(serde_json::to_value(result)?)
            }
            
            // ===== 版本控制 =====
            command::Command::VcStatus(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let status = vc.status().await?;
                Ok(serde_json::to_value(status)?)
            }
            command::Command::VcAdd(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                vc.add(&cmd.paths).await?;
                Ok(serde_json::json!({"success": true, "count": cmd.paths.len()}))
            }
            command::Command::VcCommit(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let commit_id = vc.commit(&cmd.message, cmd.author.as_deref(), cmd.author_email.as_deref()).await?;
                Ok(serde_json::json!({"success": true, "commit_id": commit_id}))
            }
            command::Command::VcLog(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let commits = vc.log(cmd.branch.as_deref(), cmd.limit).await?;
                Ok(serde_json::to_value(commits)?)
            }
            command::Command::VcDiff(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let diffs = vc.diff(cmd.path.as_deref(), cmd.staged, cmd.commit_id.as_deref()).await?;
                Ok(serde_json::to_value(diffs)?)
            }
            command::Command::VcReset(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                vc.reset(cmd.reset_type, cmd.target.as_deref(), cmd.paths.as_deref()).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::VcCreateBranch(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let name = vc.create_branch(&cmd.name, cmd.base_commit_id.as_deref(), cmd.checkout).await?;
                Ok(serde_json::json!({"success": true, "name": name}))
            }
            command::Command::VcSwitchBranch(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                vc.switch_branch(&cmd.name).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::VcDeleteBranch(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                vc.delete_branch(&cmd.name, cmd.force).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::VcStash(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let stash_id = vc.stash(cmd.message.as_deref(), cmd.include_untracked).await?;
                Ok(serde_json::json!({"success": true, "stash_id": stash_id}))
            }
            command::Command::VcStashPop(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                vc.stash_pop(cmd.stash_id.as_deref()).await?;
                Ok(serde_json::json!({"success": true}))
            }
            command::Command::VcStashList(cmd) => {
                let vc = self.get_vc_engine(cmd.repository_id).await?;
                let stashes = vc.stash_list().await?;
                Ok(serde_json::to_value(stashes)?)
            }
            
            // ===== 自动化 =====
            command::Command::ListAutomationRules(cmd) => {
                if let Some(repo_id) = cmd.repository_id {
                    let repo_db = self.get_repo_db(repo_id).await?;
                    let rules = nanosync_core::automation::AutomationService::list_rules(&repo_db).await?;
                    Ok(serde_json::to_value(rules)?)
                } else {
                    // 列出所有仓库的规则
                    let repos = self.repo_manager.list_repositories().await?;
                    let mut all_rules = Vec::new();
                    for repo in repos {
                        if let Ok(repo_db) = self.get_repo_db(repo.id).await {
                            if let Ok(rules) = nanosync_core::automation::AutomationService::list_rules(&repo_db).await {
                                all_rules.extend(rules);
                            }
                        }
                    }
                    Ok(serde_json::to_value(all_rules)?)
                }
            }
            command::Command::GetAutomationRule(cmd) => {
                // 在所有仓库中查找规则
                let repos = self.repo_manager.list_repositories().await?;
                for repo in repos {
                    if let Ok(repo_db) = self.get_repo_db(repo.id).await {
                        if let Ok(Some(rule)) = nanosync_core::automation::AutomationService::get_rule(&repo_db, &cmd.rule_id).await {
                            return Ok(serde_json::to_value(rule)?);
                        }
                    }
                }
                Ok(serde_json::json!(null))
            }
            command::Command::CreateAutomationRule(cmd) => {
                let repo_db = self.get_repo_db(cmd.request.repository_id).await?;
                let rule = nanosync_core::automation::AutomationService::create_rule(
                    &repo_db, &cmd.request, &self.device_identity
                ).await?;
                Ok(serde_json::to_value(rule)?)
            }
            command::Command::UpdateAutomationRule(cmd) => {
                // 找到仓库
                let repos = self.repo_manager.list_repositories().await?;
                for repo in repos {
                    if let Ok(repo_db) = self.get_repo_db(repo.id).await {
                        let rules = repo_db.list_automation_rules().await.unwrap_or_default();
                        if rules.iter().any(|r| r.id == cmd.request.rule_id) {
                            let rule = nanosync_core::automation::AutomationService::update_rule(&repo_db, &cmd.request).await?;
                            return Ok(serde_json::to_value(rule)?);
                        }
                    }
                }
                anyhow::bail!("规则未找到: {}", cmd.request.rule_id)
            }
            command::Command::DeleteAutomationRule(cmd) => {
                let repos = self.repo_manager.list_repositories().await?;
                for repo in repos {
                    if let Ok(repo_db) = self.get_repo_db(repo.id).await {
                        let rules = repo_db.list_automation_rules().await.unwrap_or_default();
                        if rules.iter().any(|r| r.id == cmd.rule_id) {
                            nanosync_core::automation::AutomationService::delete_rule(&repo_db, &cmd.rule_id).await?;
                            return Ok(serde_json::json!({"success": true}));
                        }
                    }
                }
                Ok(serde_json::json!({"success": false, "error": "规则未找到"}))
            }
            command::Command::ToggleAutomationRule(cmd) => {
                let repos = self.repo_manager.list_repositories().await?;
                for repo in repos {
                    if let Ok(repo_db) = self.get_repo_db(repo.id).await {
                        let rules = repo_db.list_automation_rules().await.unwrap_or_default();
                        if rules.iter().any(|r| r.id == cmd.rule_id) {
                            nanosync_core::automation::AutomationService::toggle_rule(&repo_db, &cmd.rule_id, cmd.enabled).await?;
                            return Ok(serde_json::json!({"success": true}));
                        }
                    }
                }
                Ok(serde_json::json!({"success": false, "error": "规则未找到"}))
            }
            command::Command::TakeoverAutomationRule(cmd) => {
                let repo_db = self.get_repo_db(cmd.repository_id).await?;
                let rule = nanosync_core::automation::AutomationService::takeover_rule(
                    &repo_db, &cmd.rule_id, &self.device_identity
                ).await?;
                Ok(serde_json::to_value(rule)?)
            }
            command::Command::GetAutomationRunnerStatus => {
                let status = self.automation_runner.get_status().await;
                Ok(serde_json::to_value(status)?)
            }
            
            // ===== 日志 =====
            command::Command::QueryLogs(cmd) => {
                if let Some(repo_id) = cmd.query.repository_id {
                    let repo_db = self.get_repo_db(repo_id).await?;
                    let result = self.log_service.query_logs(Some(&repo_db), &cmd.query).await?;
                    Ok(serde_json::to_value(result)?)
                } else {
                    let result = self.log_service.query_logs(None, &cmd.query).await?;
                    Ok(serde_json::to_value(result)?)
                }
            }
            command::Command::ClearLogs(cmd) => {
                if let Some(repo_id) = cmd.repository_id {
                    let repo_db = self.get_repo_db(repo_id).await?;
                    let count = self.log_service.clear_logs(Some(&repo_db)).await?;
                    Ok(serde_json::json!({"success": true, "cleared": count}))
                } else {
                    let count = self.log_service.clear_logs(None).await?;
                    Ok(serde_json::json!({"success": true, "cleared": count}))
                }
            }
            command::Command::ExportLogs(cmd) => {
                if let Some(repo_id) = cmd.request.repository_id {
                    let repo_db = self.get_repo_db(repo_id).await?;
                    let data = self.log_service.export_logs(Some(&repo_db), &cmd.request).await?;
                    let content = String::from_utf8_lossy(&data).to_string();
                    Ok(serde_json::json!({"success": true, "size": data.len(), "data": content}))
                } else {
                    let data = self.log_service.export_logs(None, &cmd.request).await?;
                    let content = String::from_utf8_lossy(&data).to_string();
                    Ok(serde_json::json!({"success": true, "size": data.len(), "data": content}))
                }
            }
            
            // ===== 设置 =====
            command::Command::GetRepositorySettings(cmd) => {
                let repo_db = self.get_repo_db(cmd.repository_id).await?;
                let settings = repo_db.get_local_settings().await?;
                Ok(serde_json::to_value(settings)?)
            }
            command::Command::SaveRepositorySettings(cmd) => {
                let repo_db = self.get_repo_db(cmd.repository_id).await?;
                repo_db.save_local_settings(&cmd.settings).await?;
                Ok(serde_json::json!({"success": true}))
            }
        }
    }

    /// 获取仓库数据库
    async fn get_repo_db(&self, repo_id: i64) -> anyhow::Result<nanosync_core::database::RepositoryDatabase> {
        let repo = self.repo_manager.get_repository(repo_id).await?
            .ok_or_else(|| anyhow::anyhow!("仓库未找到: {}", repo_id))?;
        let repo_db = nanosync_core::database::RepositoryDatabase::open(
            std::path::Path::new(&repo.local_path), repo_id
        ).await?;
        Ok(repo_db)
    }

    /// 获取版本控制引擎
    async fn get_vc_engine(&self, repo_id: i64) -> anyhow::Result<nanosync_core::version_control::VcEngine> {
        let repo = self.repo_manager.get_repository(repo_id).await?
            .ok_or_else(|| anyhow::anyhow!("仓库未找到: {}", repo_id))?;
        let vc = nanosync_core::version_control::VcEngine::new(
            repo_id,
            std::path::Path::new(&repo.local_path),
            self.device_identity.clone(),
        ).await?;
        Ok(vc)
    }
}
