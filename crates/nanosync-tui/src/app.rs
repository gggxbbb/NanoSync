//! TUI 应用状态

pub mod pages;

use crate::client::IpcClient;
use crossterm::event::KeyEvent;
use nanosync_core::models::*;
use nanosync_protocol::*;
use pages::*;

/// 当前页面
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Page {
    Repositories,
    RemoteConnections,
    VersionControl,
    Automation,
    Logs,
    Settings,
    Help,
}

/// 应用状态
pub struct App {
    /// IPC 客户端
    pub client: IpcClient,
    
    /// 当前页面
    pub current_page: Page,
    
    /// 是否应该退出
    pub should_quit: bool,
    
    /// 服务状态
    pub service_status: Option<ServiceStatus>,
    
    /// 仓库列表页
    pub repositories_page: RepositoriesPage,
    
    /// 远程连接页
    pub remote_connections_page: RemoteConnectionsPage,
    
    /// 版本控制页
    pub version_control_page: VersionControlPage,
    
    /// 自动化页
    pub automation_page: AutomationPage,
    
    /// 日志页
    pub logs_page: LogsPage,
    
    /// 消息/错误提示
    pub message: Option<(String, MessageType)>,
    
    /// 是否加载中
    pub is_loading: bool,
}

/// 消息类型
#[derive(Debug, Clone, Copy)]
pub enum MessageType {
    Info,
    Success,
    Warning,
    Error,
}

impl App {
    pub fn new(ipc_address: &str) -> Self {
        Self {
            client: IpcClient::new(ipc_address),
            current_page: Page::Repositories,
            should_quit: false,
            service_status: None,
            repositories_page: RepositoriesPage::default(),
            remote_connections_page: RemoteConnectionsPage::default(),
            version_control_page: VersionControlPage::default(),
            automation_page: AutomationPage::default(),
            logs_page: LogsPage::default(),
            message: None,
            is_loading: false,
        }
    }

    pub fn should_quit(&self) -> bool {
        self.should_quit
    }

    pub async fn handle_key(&mut self, key: KeyEvent) -> anyhow::Result<()> {
        // 全局按键
        match key.code {
            crossterm::event::KeyCode::Char('1') => self.current_page = Page::Repositories,
            crossterm::event::KeyCode::Char('2') => self.current_page = Page::RemoteConnections,
            crossterm::event::KeyCode::Char('3') => self.current_page = Page::VersionControl,
            crossterm::event::KeyCode::Char('4') => self.current_page = Page::Automation,
            crossterm::event::KeyCode::Char('5') => self.current_page = Page::Logs,
            crossterm::event::KeyCode::Char('6') => self.current_page = Page::Settings,
            crossterm::event::KeyCode::Char('?') => self.current_page = Page::Help,
            crossterm::event::KeyCode::Char('r') => {
                self.refresh_current_page().await?;
            }
            _ => {}
        }

        // 页面特定按键
        match self.current_page {
            Page::Repositories => self.repositories_page.handle_key(key).await?,
            Page::RemoteConnections => self.remote_connections_page.handle_key(key).await?,
            Page::VersionControl => self.version_control_page.handle_key(key).await?,
            Page::Automation => self.automation_page.handle_key(key).await?,
            Page::Logs => self.logs_page.handle_key(key).await?,
            Page::Settings => {}
            Page::Help => {}
        }

        Ok(())
    }

    pub async fn refresh_current_page(&mut self) -> anyhow::Result<()> {
        self.is_loading = true;
        
        match self.current_page {
            Page::Repositories => {
                let response = self.client.send_command(command::Command::ListRepositories).await?;
                if let Some(repos) = response.parse::<Vec<RegisteredRepository>>().ok() {
                    self.repositories_page.repositories = repos;
                }
            }
            Page::RemoteConnections => {
                let response = self.client.send_command(command::Command::ListRemoteConnections).await?;
                if let Some(conns) = response.parse::<Vec<RemoteConnection>>().ok() {
                    self.remote_connections_page.connections = conns;
                }
            }
            _ => {}
        }

        self.is_loading = false;
        Ok(())
    }

    pub fn show_message(&mut self, message: &str, msg_type: MessageType) {
        self.message = Some((message.to_string(), msg_type));
    }

    pub fn clear_message(&mut self) {
        self.message = None;
    }
}

/// 仓库列表页
#[derive(Default)]
pub struct RepositoriesPage {
    pub repositories: Vec<RegisteredRepository>,
    pub selected_index: usize,
}

impl RepositoriesPage {
    pub async fn handle_key(&mut self, key: KeyEvent) -> anyhow::Result<()> {
        match key.code {
            crossterm::event::KeyCode::Up => {
                if self.selected_index > 0 {
                    self.selected_index -= 1;
                }
            }
            crossterm::event::KeyCode::Down => {
                if self.selected_index < self.repositories.len().saturating_sub(1) {
                    self.selected_index += 1;
                }
            }
            _ => {}
        }
        Ok(())
    }
}

/// 远程连接页
#[derive(Default)]
pub struct RemoteConnectionsPage {
    pub connections: Vec<RemoteConnection>,
    pub selected_index: usize,
}

impl RemoteConnectionsPage {
    pub async fn handle_key(&mut self, key: KeyEvent) -> anyhow::Result<()> {
        match key.code {
            crossterm::event::KeyCode::Up => {
                if self.selected_index > 0 {
                    self.selected_index -= 1;
                }
            }
            crossterm::event::KeyCode::Down => {
                if self.selected_index < self.connections.len().saturating_sub(1) {
                    self.selected_index += 1;
                }
            }
            _ => {}
        }
        Ok(())
    }
}

/// 版本控制页
#[derive(Default)]
pub struct VersionControlPage {
    pub selected_repository: Option<i64>,
    pub status: Option<WorkingDirectoryStatus>,
    pub commits: Vec<Commit>,
}

impl VersionControlPage {
    pub async fn handle_key(&mut self, _key: KeyEvent) -> anyhow::Result<()> {
        Ok(())
    }
}

/// 自动化页
#[derive(Default)]
pub struct AutomationPage {
    pub rules: Vec<AutomationRule>,
    pub selected_index: usize,
}

impl AutomationPage {
    pub async fn handle_key(&mut self, key: KeyEvent) -> anyhow::Result<()> {
        match key.code {
            crossterm::event::KeyCode::Up => {
                if self.selected_index > 0 {
                    self.selected_index -= 1;
                }
            }
            crossterm::event::KeyCode::Down => {
                if self.selected_index < self.rules.len().saturating_sub(1) {
                    self.selected_index += 1;
                }
            }
            _ => {}
        }
        Ok(())
    }
}

/// 日志页
#[derive(Default)]
pub struct LogsPage {
    pub logs: Vec<AppLogEntry>,
    pub selected_index: usize,
    pub filter_level: Option<LogLevel>,
}

impl LogsPage {
    pub async fn handle_key(&mut self, key: KeyEvent) -> anyhow::Result<()> {
        match key.code {
            crossterm::event::KeyCode::Up => {
                if self.selected_index > 0 {
                    self.selected_index -= 1;
                }
            }
            crossterm::event::KeyCode::Down => {
                if self.selected_index < self.logs.len().saturating_sub(1) {
                    self.selected_index += 1;
                }
            }
            _ => {}
        }
        Ok(())
    }
}