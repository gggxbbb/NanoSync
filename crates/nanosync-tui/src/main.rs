//! NanoSync TUI 前端

mod app;
mod ui;
mod client;

use clap::Parser;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    Terminal,
};
use std::io;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser)]
#[command(name = "nanosync-tui")]
#[command(about = "NanoSync TUI 控制端")]
#[command(version)]
struct Cli {
    /// IPC 地址
    #[arg(short, long, default_value = DEFAULT_IPC_ADDRESS)]
    ipc: String,
    
    /// 启用调试日志
    #[arg(short, long)]
    debug: bool,
}

#[cfg(windows)]
const DEFAULT_IPC_ADDRESS: &str = r"\\.\pipe\nanosyncd";

#[cfg(not(windows))]
const DEFAULT_IPC_ADDRESS: &str = "/tmp/nanosyncd.sock";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 初始化日志
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    // 设置终端
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // 创建应用
    let mut app = app::App::new(&cli.ipc);

    // 主循环
    let res = run_app(&mut terminal, &mut app).await;

    // 恢复终端
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        eprintln!("错误: {}", err);
    }

    Ok(())
}

async fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    app: &mut app::App,
) -> anyhow::Result<()> {
    loop {
        // 绘制 UI
        terminal.draw(|f| ui::draw(f, app))?;

        // 处理事件
        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                match (key.modifiers, key.code) {
                    (KeyModifiers::CONTROL, KeyCode::Char('c')) => {
                        return Ok(());
                    }
                    (KeyModifiers::NONE, KeyCode::Char('q')) => {
                        return Ok(());
                    }
                    _ => {
                        app.handle_key(key).await?;
                    }
                }
            }
        }

        // 检查是否退出
        if app.should_quit() {
            return Ok(());
        }
    }
}