//! TUI UI 渲染

use crate::app::{App, Page};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Tabs},
    Frame,
};

/// 绘制主界面
pub fn draw(f: &mut Frame, app: &App) {
    // 创建主布局
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([
            Constraint::Length(3),  // 标题和标签
            Constraint::Min(0),      // 主内容
            Constraint::Length(3),  // 状态栏
        ])
        .split(f.size());

    // 绘制标签页
    draw_tabs(f, chunks[0], app);

    // 绘制主内容
    match app.current_page {
        Page::Repositories => draw_repositories_page(f, chunks[1], app),
        Page::RemoteConnections => draw_remote_connections_page(f, chunks[1], app),
        Page::VersionControl => draw_version_control_page(f, chunks[1], app),
        Page::Automation => draw_automation_page(f, chunks[1], app),
        Page::Logs => draw_logs_page(f, chunks[1], app),
        Page::Settings => draw_settings_page(f, chunks[1], app),
        Page::Help => draw_help_page(f, chunks[1], app),
    }

    // 绘制状态栏
    draw_status_bar(f, chunks[2], app);
}

/// 绘制标签页
fn draw_tabs(f: &mut Frame, area: Rect, app: &App) {
    let titles = vec![
        "1:仓库", "2:远程", "3:版本", "4:自动化", "5:日志", "6:设置", "?:帮助",
    ];
    
    let tabs = Tabs::new(titles.iter().map(|t| Line::from(*t)).collect::<Vec<_>>())
        .block(Block::default().borders(Borders::ALL).title("NanoSync"))
        .select(match app.current_page {
            Page::Repositories => 0,
            Page::RemoteConnections => 1,
            Page::VersionControl => 2,
            Page::Automation => 3,
            Page::Logs => 4,
            Page::Settings => 5,
            Page::Help => 6,
        })
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD));

    f.render_widget(tabs, area);
}

/// 绘制仓库列表页
fn draw_repositories_page(f: &mut Frame, area: Rect, app: &App) {
    let items: Vec<ListItem> = app.repositories_page.repositories
        .iter()
        .enumerate()
        .map(|(i, repo)| {
            let style = if i == app.repositories_page.selected_index {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            
            ListItem::new(Line::from(vec![
                Span::styled(&repo.name, style),
                Span::raw(" - "),
                Span::styled(&repo.local_path, Style::default().fg(Color::DarkGray)),
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title("仓库列表"))
        .highlight_style(Style::default().bg(Color::DarkGray));

    f.render_widget(list, area);
}

/// 绘制远程连接页
fn draw_remote_connections_page(f: &mut Frame, area: Rect, app: &App) {
    let items: Vec<ListItem> = app.remote_connections_page.connections
        .iter()
        .enumerate()
        .map(|(i, conn)| {
            let style = if i == app.remote_connections_page.selected_index {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            
            ListItem::new(Line::from(vec![
                Span::styled(&conn.name, style),
                Span::raw(" ("),
                Span::styled(&conn.protocol, Style::default().fg(Color::Cyan)),
                Span::raw(") - "),
                Span::styled(&conn.host, Style::default().fg(Color::DarkGray)),
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title("远程连接"))
        .highlight_style(Style::default().bg(Color::DarkGray));

    f.render_widget(list, area);
}

/// 绘制版本控制页
fn draw_version_control_page(f: &mut Frame, area: Rect, app: &App) {
    let vc_page = &app.version_control_page;

    if vc_page.selected_repository.is_none() {
        // 显示仓库选择提示
        let paragraph = Paragraph::new(
            "版本控制\n\n请先在「仓库」页面选择一个仓库\n按 1 切换到仓库页面"
        )
        .block(Block::default().borders(Borders::ALL).title("版本控制"))
        .style(Style::default().fg(Color::DarkGray));
        f.render_widget(paragraph, area);
        return;
    }

    // 分割布局：上方是状态/历史标签, 下方是内容
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)])
        .split(area);

    // 标签
    let tab_titles = vec!["工作区状态", "提交历史"];
    let tabs = Tabs::new(tab_titles.iter().map(|t| Line::from(*t)).collect::<Vec<_>>())
        .block(Block::default().borders(Borders::ALL).title("版本控制"))
        .select(vc_page.selected_tab)
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD));
    f.render_widget(tabs, chunks[0]);

    match vc_page.selected_tab {
        0 => draw_vc_status(f, chunks[1], vc_page),
        1 => draw_vc_log(f, chunks[1], vc_page),
        _ => {}
    }
}

/// 绘制工作区状态
fn draw_vc_status(f: &mut Frame, area: Rect, page: &crate::app::VersionControlPage) {
    if let Some(status) = &page.status {
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(area);

        // 左侧：已暂存变更
        let staged_items: Vec<ListItem> = status.staged_changes
            .iter()
            .map(|e| {
                let icon = match e.change_type {
                    nanosync_core::models::ChangeType::Added => "A",
                    nanosync_core::models::ChangeType::Modified => "M",
                    nanosync_core::models::ChangeType::Deleted => "D",
                    _ => "?",
                };
                ListItem::new(Line::from(vec![
                    Span::styled(format!(" {} ", icon), Style::default().fg(Color::Green)),
                    Span::raw(&e.path),
                ]))
            })
            .collect();

        let staged_list = List::new(staged_items)
            .block(Block::default().borders(Borders::ALL)
                .title(format!("已暂存 ({})", status.staged_changes.len())));
        f.render_widget(staged_list, chunks[0]);

        // 右侧：未暂存变更
        let unstaged_items: Vec<ListItem> = status.unstaged_changes
            .iter()
            .map(|e| {
                let icon = match e.change_type {
                    nanosync_core::models::ChangeType::Added => "A",
                    nanosync_core::models::ChangeType::Modified => "M",
                    nanosync_core::models::ChangeType::Deleted => "D",
                    _ => "?",
                };
                ListItem::new(Line::from(vec![
                    Span::styled(format!(" {} ", icon), Style::default().fg(Color::Yellow)),
                    Span::raw(&e.path),
                ]))
            })
            .collect();

        let status_info = if status.is_clean { "✓ 干净" } else { "有变更" };
        let branch_info = status.current_branch.as_deref().unwrap_or("(无分支)");
        let title = format!("未暂存 ({}) [{}] [{}]", 
            status.unstaged_changes.len(), branch_info, status_info);

        let unstaged_list = List::new(unstaged_items)
            .block(Block::default().borders(Borders::ALL).title(title));
        f.render_widget(unstaged_list, chunks[1]);
    } else {
        let paragraph = Paragraph::new("按 r 刷新工作区状态")
            .block(Block::default().borders(Borders::ALL).title("工作区状态"))
            .style(Style::default().fg(Color::DarkGray));
        f.render_widget(paragraph, area);
    }
}

/// 绘制提交历史
fn draw_vc_log(f: &mut Frame, area: Rect, page: &crate::app::VersionControlPage) {
    let items: Vec<ListItem> = page.commits
        .iter()
        .enumerate()
        .map(|(i, commit)| {
            let style = if i == page.selected_index {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let short_id: String = commit.id.chars().take(8).collect();
            let time = commit.timestamp.format("%m-%d %H:%M").to_string();

            ListItem::new(Line::from(vec![
                Span::styled(format!("{} ", short_id), Style::default().fg(Color::Cyan)),
                Span::raw(format!("[{}] ", time)),
                Span::styled(&commit.message, style),
                Span::styled(format!(" <{}>", commit.author), Style::default().fg(Color::DarkGray)),
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL)
            .title(format!("提交历史 ({})", page.commits.len())))
        .highlight_style(Style::default().bg(Color::DarkGray));

    f.render_widget(list, area);
}

/// 绘制自动化页
fn draw_automation_page(f: &mut Frame, area: Rect, app: &App) {
    let items: Vec<ListItem> = app.automation_page.rules
        .iter()
        .enumerate()
        .map(|(i, rule)| {
            let style = if i == app.automation_page.selected_index {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            
            let enabled = if rule.enabled { "✓" } else { "✗" };
            
            ListItem::new(Line::from(vec![
                Span::styled(enabled, if rule.enabled {
                    Style::default().fg(Color::Green)
                } else {
                    Style::default().fg(Color::Red)
                }),
                Span::raw(" "),
                Span::styled(&rule.name, style),
                Span::raw(" - "),
                Span::styled(
                    format!("{:?}", rule.trigger_type),
                    Style::default().fg(Color::Cyan)
                ),
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title("自动化规则"))
        .highlight_style(Style::default().bg(Color::DarkGray));

    f.render_widget(list, area);
}

/// 绘制日志页
fn draw_logs_page(f: &mut Frame, area: Rect, app: &App) {
    let items: Vec<ListItem> = app.logs_page.logs
        .iter()
        .enumerate()
        .map(|(i, log)| {
            let style = if i == app.logs_page.selected_index {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            
            let level_color = match log.level {
                nanosync_core::models::LogLevel::Debug => Color::DarkGray,
                nanosync_core::models::LogLevel::Info => Color::Green,
                nanosync_core::models::LogLevel::Warning => Color::Yellow,
                nanosync_core::models::LogLevel::Error => Color::Red,
            };
            
            ListItem::new(Line::from(vec![
                Span::styled(
                    format!("[{}]", log.level),
                    Style::default().fg(level_color),
                ),
                Span::raw(" "),
                Span::styled(&log.message, style),
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title("日志"))
        .highlight_style(Style::default().bg(Color::DarkGray));

    f.render_widget(list, area);
}

/// 绘制设置页
fn draw_settings_page(f: &mut Frame, area: Rect, _app: &App) {
    let paragraph = Paragraph::new("设置页面\n\n[待实现]")
        .block(Block::default().borders(Borders::ALL).title("设置"));
    f.render_widget(paragraph, area);
}

/// 绘制帮助页
fn draw_help_page(f: &mut Frame, area: Rect, _app: &App) {
    let help_text = r#"
NanoSync TUI 帮助

快捷键:
  1-6     切换页面
  ?       显示帮助
  q       退出
  r       刷新当前页面
  ↑/↓     列表导航
  Enter   选择/确认
  Esc     返回/取消

页面说明:
  仓库     管理本地仓库
  远程     管理远程连接
  版本     版本控制操作
  自动化   管理自动化规则
  日志     查看应用日志
  设置     应用设置
"#;

    let paragraph = Paragraph::new(help_text)
        .block(Block::default().borders(Borders::ALL).title("帮助"));
    f.render_widget(paragraph, area);
}

/// 绘制状态栏
fn draw_status_bar(f: &mut Frame, area: Rect, app: &App) {
    let status = if app.is_loading {
        "加载中..."
    } else if let Some((msg, _)) = &app.message {
        msg.as_str()
    } else {
        "按 ? 查看帮助 | q 退出"
    };

    let paragraph = Paragraph::new(status)
        .style(Style::default().fg(Color::White))
        .block(Block::default().borders(Borders::ALL));

    f.render_widget(paragraph, area);
}