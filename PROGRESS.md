# NanoSync Rust TUI 项目进度记录

**最后更新**: 2026-03-27 23:13 (UTC+8)

## 项目概述

将 NanoSync 从 Flutter 重构为 Rust TUI 架构，包含两个可执行文件：
- `nanosyncd` - 后台服务守护进程
- `nanosync-tui` - TUI 前端界面

## 编译状态

| Crate | 状态 | 备注 |
|-------|------|------|
| nanosync-core | ✅ 编译成功 (有警告) | 核心库 |
| nanosync-protocol | ✅ 编译成功 (有警告) | IPC 协议 |
| nanosyncd | 🔄 修复中 | Windows 服务 API 已更新 |
| nanosync-tui | ⏳ 待验证 | TUI 前端 |

## 已完成的工作

### 1. 项目结构 ✅
- 创建了 Cargo workspace 结构
- 4 个 crate: nanosync-core, nanosync-protocol, nanosyncd, nanosync-tui
- 配置了所有依赖项

### 2. nanosync-core 核心库 ✅
- **数据模型** (`models/`)
  - `repository.rs` - 仓库模型
  - `remote.rs` - 远程连接模型 (SMB/WebDAV/UNC)
  - `version_control.rs` - 版本控制模型 (Commit, Branch, Stash, DiffResult)
  - `automation.rs` - 自动化规则模型
  - `sync.rs` - 同步状态模型
  - `log.rs` - 日志模型

- **数据库** (`database/`)
  - `manager.rs` - 软件级数据库管理器
  - `repository.rs` - 仓库级数据库
  - `schema.rs` - 数据库 schema 定义

- **设备指纹** (`device.rs`)
  - DeviceIdentity 结构
  - 多设备同步隔离支持

- **仓库管理** (`repository/manager.rs`)
  - 仓库注册/注销/导入
  - 仓库状态管理

- **远程连接** (`remote/`)
  - `manager.rs` - 远程连接管理器
  - `smb.rs` - SMB 客户端 (stub)
  - `webdav.rs` - WebDAV 客户端 (stub)
  - `unc.rs` - UNC 路径处理 (stub)

- **同步引擎** (`sync/engine.rs`)
  - fetch/push/pull/sync 操作 (stub)

- **版本控制引擎** (`version_control/engine.rs`)
  - stage/commit/branch/stash 操作 (stub)

- **自动化运行器** (`automation/runner.rs`)
  - 15 秒 tick 周期调度

- **日志服务** (`logging/service.rs`)
  - 应用日志记录

- **工具函数** (`utils/`)
  - `file.rs` - 文件操作
  - `hash.rs` - 哈希计算
  - `ignore.rs` - ignore 规则解析
  - `path.rs` - 路径处理

### 3. nanosync-protocol IPC 协议 ✅
- **消息格式** (`message.rs`)
  - IpcMessage 结构
  - MessageKind 枚举

- **命令定义** (`command.rs`)
  - 完整的命令集定义
  - 请求/响应类型

- **事件定义** (`event.rs`)
  - 同步进度事件
  - 自动化触发事件

- **编解码器** (`codec.rs`)
  - MessageCodec 实现

### 4. nanosyncd 后台服务 🔄
- **主程序** (`main.rs`)
  - CLI 参数解析 (clap)
  - run/install/uninstall/status 子命令

- **IPC 服务** (`ipc.rs`)
  - Windows 命名管道实现
  - Unix socket 实现 (条件编译)
  - 客户端处理

- **Windows 服务** (`service/windows.rs`)
  - 服务安装/卸载
  - 已修复 windows-service 0.8 API 兼容性
    - `ServiceType::OwnProcess` → `ServiceType::OWN_PROCESS`
    - `ServiceStartType::Auto` → `ServiceStartType::AutoStart`

- **配置** (`config.rs`)
  - 服务配置结构

### 5. nanosync-tui TUI 前端 ⏳
- **主程序** (`main.rs`)
  - CLI 参数
  - IPC 地址配置

- **应用状态** (`app.rs`)
  - App 状态结构
  - 页面导航

- **UI 渲染** (`ui.rs`)
  - 主界面布局
  - 各页面渲染

- **IPC 客户端** (`client.rs`)
  - IpcClient 实现

## 待修复的问题

### 编译警告 (非阻塞)
1. **nanosync-core**
   - ambiguous glob re-exports (SyncType, SyncStatus, ConflictResolution)
   - 多个 unused imports
   - 多个 unused variables
   - dead_code 警告 (SmbClient, WebDavClient, SyncEngine 字段)

2. **nanosync-protocol**
   - unused import: MessageKind
   - unused variable: temp
   - unnecessary mut

### 待实现的功能 (Stub 代码)
1. **远程连接**
   - SMB 客户端实际实现
   - WebDAV 客户端实际实现
   - UNC 路径处理

2. **同步引擎**
   - 实际的文件同步逻辑
   - 冲突检测和处理
   - 增量同步

3. **版本控制引擎**
   - 实际的 diff 算法
   - 文件快照管理
   - 合并冲突处理

4. **日志系统**
   - 日志持久化
   - 日志轮转

## 下一步计划

1. 验证 nanosyncd 编译通过
2. 验证 nanosync-tui 编译通过
3. 清理编译警告
4. 实现核心功能 (去除 stub)
5. 添加集成测试
6. 编写文档

## 技术栈

- Rust 1.89.0
- Tokio 异步运行时
- SQLx + SQLite 数据库
- Ratatui TUI 框架
- Clap CLI 解析
- Tracing 日志
- windows-service 0.8 (Windows 服务)
