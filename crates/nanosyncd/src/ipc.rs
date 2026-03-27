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
                let status = ServiceStatus {
                    version: env!("CARGO_PKG_VERSION").to_string(),
                    uptime_seconds: self.start_time.elapsed().as_secs(),
                    repositories_count: 0,
                    active_syncs: 0,
                    automation_running: false,
                };
                Ok(serde_json::to_value(status)?)
            }
            command::Command::Shutdown => {
                let _ = self.stop_tx.send(());
                Ok(serde_json::json!({"success": true}))
            }
            
            // 仓库管理
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
            
            // 远程连接管理
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
            
            // 同步操作
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
            
            // 其他命令...
            _ => {
                Ok(serde_json::json!({"error": "命令未实现"}))
            }
        }
    }
}
