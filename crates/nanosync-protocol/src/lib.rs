//! NanoSync IPC 协议定义
//!
//! 定义 TUI 前端和后台服务之间的通信协议

pub mod message;
pub mod command;
pub mod event;
pub mod codec;

pub use message::*;
pub use command::*;
pub use event::*;
pub use codec::*;

/// IPC 协议版本
pub const PROTOCOL_VERSION: &str = "1.0.0";

/// 默认 IPC 管道名称
#[cfg(target_os = "windows")]
pub const DEFAULT_PIPE_NAME: &str = r"\\.\pipe\nanosyncd";

/// 默认 Unix socket 路径
#[cfg(not(target_os = "windows"))]
pub const DEFAULT_SOCKET_PATH: &str = "/tmp/nanosyncd.sock";