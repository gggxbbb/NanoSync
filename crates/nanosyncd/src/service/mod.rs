//! 服务相关模块

#[cfg(windows)]
pub mod windows;

#[cfg(not(windows))]
pub mod unix;