# NanoSync Rust TUI 项目进度记录

**最后更新**: 2026-03-29 (UTC+8)

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

### 0. 本轮增量 (2026-03-29) ✅
- 远程连接测试不再固定返回成功：
  - SMB: 增加 TCP 可达性探测（端口超时检测）
  - WebDAV: 增加 HTTP OPTIONS 探测（支持基础认证，返回真实 HTTP 状态）
  - UNC: 通过 UNC 路径可达性返回成功/失败
- WebDAV 文件操作新增基础实现：
  - 下载（GET）、上传（PUT）、删除（DELETE）
  - 目录确保存在（MKCOL）
  - 文件存在性/元信息（HEAD）
  - 基础目录列举（PROPFIND 结果解析）
- 删除远程连接前新增“仓库引用检查”，防止误删被绑定连接
- 同步引擎新增最小可用状态同步能力：
  - fetch: 可拉取远端 `repository_state.json`（WebDAV/UNC）并计算 ahead/behind（不再固定 0）
  - push: 可导出并上传本地 `repository_state.json`（WebDAV/UNC）
  - get_sync_status: 改为基于 fetch 结果返回
  - 新增 SMB 路径支持：可按 share 路径（如 `/public/project`）拉取/推送状态文件
- 对象传输新增基础实现：
  - push: 上传本地缺失对象到远端 `.nanosync/objects`
  - fetch/pull: 基于远端 `.nanosync/object_index.json` 下载本地缺失对象
- pull 新增最小快进元数据应用：可按远端状态更新本地分支 head 与默认分支
- ahead/behind 计算增强：支持基于提交 DAG 的祖先距离计算
- pull 安全检查：工作区存在未提交变更时拒绝应用远端状态
- pull 内容级最小落地：按远端文件索引更新本地工作区（写入/更新/删除）并同步本地对象索引
- 修复 `nanosyncd` 编译错误：`main.rs` 中 Install/Uninstall 命令分支错误丢弃 `name` 参数导致未定义变量，已修复并通过编译
- 新增根目录 `README.md`，补充 Rust workspace 架构、启动方式、已实现能力与已知缺口

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
  - `smb.rs` - SMB 客户端（已实现基础 TCP 可达性检测）
  - `webdav.rs` - WebDAV 客户端（已实现基础 HTTP 连通性检测）
  - `unc.rs` - UNC 路径处理

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
- SMB 协议级增强（共享自动枚举、严格凭证校验）
- WebDAV 完整兼容性增强（复杂服务端 PROPFIND 解析、递归列举、权限细分）

### 同步引擎实际实现
- 冲突检测和处理
- 增量同步优化（当前对象传输为基础实现，尚未做精细差量策略）
- ahead/behind 精细化策略与性能优化（当前已支持 DAG 距离计算）

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
