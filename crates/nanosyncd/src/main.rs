//! NanoSync 后台服务 (nanosyncd)
//!
//! 常驻进程，管理数据库、文件扫描、同步执行、自动化调度、日志

mod service;
mod ipc;
mod config;

use clap::{Parser, Subcommand};
use nanosync_core::database::DatabaseManager;
use nanosync_core::device::DeviceIdentity;
use nanosync_core::repository::RepositoryManager;
use nanosync_core::remote::RemoteConnectionManager;
use nanosync_core::sync::SyncEngine;
use nanosync_core::automation::AutomationRunner;
use nanosync_core::logging::LogService;
use std::sync::Arc;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

const DEFAULT_DB_PATH: &str = "nanosync.db";

fn get_default_db_path() -> String {
    let data_dir = directories::ProjectDirs::from("com", "nanosync", "nanosyncd")
        .map(|d| d.data_dir().to_path_buf())
        .unwrap_or_else(|| std::env::current_dir().unwrap());
    
    format!("{}/nanosync.db", data_dir.to_string_lossy())
}

#[derive(Parser)]
#[command(name = "nanosyncd")]
#[command(about = "NanoSync 后台服务")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 以前台模式运行服务
    Run {
        /// 数据库路径
        #[arg(short, long, default_value = DEFAULT_DB_PATH)]
        db: String,
        
        /// 是否启用调试日志
        #[arg(short, long)]
        debug: bool,
    },
    
    /// 安装为系统服务
    Install {
        /// 服务名称
        #[arg(long, default_value = "nanosyncd")]
        name: String,
    },
    
    /// 卸载系统服务
    Uninstall {
        /// 服务名称
        #[arg(long, default_value = "nanosyncd")]
        name: String,
    },
    
    /// 检查服务状态
    Status,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 初始化日志
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Run { db, debug } => {
            run_service(&db, debug).await?;
        }
        Commands::Install { name } => {
            #[cfg(windows)]
            {
                service::windows::install_service(&name)?;
            }
            #[cfg(not(windows))]
            {
                println!("自动安装服务仅在 Windows 上支持");
                println!("请手动配置 systemd 或其他 init 系统");
            }
        }
        Commands::Uninstall { name } => {
            #[cfg(windows)]
            {
                service::windows::uninstall_service(&name)?;
            }
            #[cfg(not(windows))]
            {
                println!("自动卸载服务仅在 Windows 上支持");
            }
        }
        Commands::Status => {
            println!("服务状态检查...");
            // TODO: 检查服务是否运行
        }
    }

    Ok(())
}

/// 运行服务
async fn run_service(db_path: &str, debug: bool) -> anyhow::Result<()> {
    use tracing::info;

    info!("NanoSync 服务启动中...");
    info!("数据库路径: {}", db_path);

    // 确保数据库目录存在
    let db_path = std::path::Path::new(db_path);
    if let Some(parent) = db_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // 获取设备身份
    let device_identity = DeviceIdentity::default();
    info!("设备指纹: {}", device_identity.fingerprint);

    // 初始化数据库
    let db = Arc::new(DatabaseManager::open(db_path).await?);
    info!("数据库初始化完成");

    // 创建各管理器
    let repo_manager = Arc::new(RepositoryManager::new(db.clone(), device_identity.clone()));
    let remote_manager = Arc::new(RemoteConnectionManager::new(db.clone()));
    let sync_engine = Arc::new(SyncEngine::new(
        db.clone(),
        repo_manager.clone(),
        remote_manager.clone(),
        device_identity.clone(),
    ));
    let log_service = Arc::new(LogService::new(device_identity.clone()));

    // 检查是否有启用的自动化规则，决定是否启动 runner
    let automation_runner = Arc::new(AutomationRunner::new(
        repo_manager.clone(),
        sync_engine.clone(),
        device_identity.clone(),
    ));

    // 启动 IPC 服务
    let ipc_server = ipc::IpcServer::new(
        db.clone(),
        repo_manager.clone(),
        remote_manager.clone(),
        sync_engine.clone(),
        automation_runner.clone(),
        log_service.clone(),
        device_identity.clone(),
    );

    info!("服务启动完成，等待连接...");

    // 运行 IPC 服务
    ipc_server.run().await?;

    info!("服务停止");
    Ok(())
}