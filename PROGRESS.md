# NanoSync Rust TUI 项目进度记录

**最后更新**: 2026-03-28 (UTC+8)

## 项目概述

将 NanoSync 从 Flutter 重构为 Rust TUI 架构，包含两个可执行文件：
- `nanosyncd` - 后台服务守护进程
- `nanosync-tui` - TUI 前端界面

## 编译状态

| Crate | 状态 | 备注 |
|-------|------|------|
| nanosync-core | ✅ 编译成功 | 核心库 |
| nanosync-protocol | ✅ 编译成功 | IPC 协议 |
| nanosyncd | ✅ 编译成功 | 后台服务 |
| nanosync-tui | ✅ 编译成功 | TUI 前端 |

## 已完成的工作

### 1. 项目结构 ✅
- 创建了 Cargo workspace 结构
- 4 个 crate: nanosync-core, nanosync-protocol, nanosyncd, nanosync-tui
- 配置了所有依赖项

### 2. nanosync-core 核心库 ✅
- **数据模型** (`models/`)
  - `repository.rs` - 仓库模型
  - `remote.rs` - 远程连接模型 (SMB/WebDAV/UNC)
  - `version_control.rs` - 版本控制模型 (Commit, Branch, Stash, DiffResult, ObjectIndexEntry)
  - `automation.rs` - 自动化规则模型
  - `sync.rs` - 同步状态模型
  - `log.rs` - 日志模型
  - 修复了 SyncType/SyncStatus 的 glob re-export 歧义问题

- **数据库** (`database/`)
  - `manager.rs` - 软件级数据库管理器
  - `repository.rs` - 仓库级数据库（新增 Stash 管理、对象索引、日志清空、远端删除）
  - `schema.rs` - 数据库 schema（新增 object_index 表）

- **设备指纹** (`device.rs`)
  - DeviceIdentity 结构
  - 多设备同步隔离支持

- **仓库管理** (`repository/manager.rs`)
  - 仓库注册/注销/导入/迁移

- **远程连接** (`remote/`)
  - `manager.rs` - 远程连接管理器（含直接测试功能）
  - `smb.rs` - SMB 客户端 (stub)
  - `webdav.rs` - WebDAV 客户端 (stub)
  - `unc.rs` - UNC 路径处理 (stub)

- **同步引擎** (`sync/engine.rs`)
  - fetch/push/pull/sync 操作 (基础框架)

- **版本控制引擎** (`version_control/engine.rs`) ✅ 核心实现完成
  - **工作区扫描**: 扫描工作目录，自动检测未暂存变更（新增/修改/删除）
  - **对象存储**: add() 计算文件 BLAKE3 哈希，存储到 .nanosync/objects
  - **提交**: commit() 更新对象索引，记录每个文件的提交状态
  - **Diff**: diff() 对比工作区与上次提交，生成 unified diff 格式
  - **分支**: create_branch/switch_branch/delete_branch
  - **Stash**: stash/stash_pop/stash_list（完整实现）
  - **忽略规则**: 集成 IgnoreManager

- **自动化运行器** (`automation/runner.rs`)
  - 15 秒 tick 周期调度
  - ChangeBased 触发类型：防抖处理

- **日志服务** (`logging/service.rs`)
  - 应用日志记录、查询、导出（JSON/CSV/文本）

- **工具函数** (`utils/`)
  - `file.rs` - 文件操作
  - `hash.rs` - 哈希计算 (BLAKE3)
  - `ignore.rs` - ignore 规则解析
  - `path.rs` - 路径处理

### 3. nanosync-protocol IPC 协议 ✅
- 完整命令集、消息格式、编解码器

### 4. nanosyncd 后台服务 ✅
- **IPC 服务** (`ipc.rs`) - 所有命令已实现：
  - 仓库管理：注册/注销/导入/迁移/删除
  - 远程连接管理：CRUD + 测试
  - 仓库远端绑定：绑定/解绑/设置默认
  - 同步操作：fetch/push/pull/sync/status
  - 版本控制：status/add/commit/log/diff/reset/branch/stash
  - 自动化：CRUD + 切换/接管/状态查询
  - 日志：查询/清空/导出
  - 设置：获取/保存仓库设置

### 5. nanosync-tui TUI 前端 ✅
- 主界面布局（标签页导航）
- 版本控制页面：显示已暂存/未暂存变更、分支信息、提交历史（Tab 切换）
- 仓库列表页、远程连接页、自动化页、日志页

## 待实现的功能

### 远程连接实际实现 (Stub)
- SMB 客户端实际连接实现
- WebDAV 客户端实际连接实现
- UNC 路径处理

### 同步引擎实际实现
- 实际的文件同步逻辑（对象传输）
- 冲突检测和处理
- 增量同步
- ahead/behind 实际计算

### 其他
- 合并冲突处理
- 日志轮转
- 集成测试

## 技术栈

- Rust 1.89.0
- Tokio 异步运行时
- SQLx + SQLite 数据库
- Ratatui 0.26 TUI 框架
- Clap CLI 解析
- Tracing 日志
- windows-service 0.8 (Windows 服务)
- BLAKE3 哈希算法
- WalkDir 目录遍历
