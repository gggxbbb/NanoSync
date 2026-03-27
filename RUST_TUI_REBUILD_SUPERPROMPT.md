# NanoSync 现状全量功能与逻辑总览 + Rust TUI/常驻服务重构超长 Prompt

你现在要接手一个已经迭代过多轮的 Windows 桌面同步工具项目 NanoSync，并将其重构为：

- 控制端：Rust + TUI
- 后台端：Rust 常驻服务进程（守护进程 / Windows Service 风格）
- 两者通过本地 IPC 通信

本提示词目标：完整描述当前项目已实现功能和逻辑，确保重构时不丢失核心行为，同时明确当前缺陷与技术债，指导你做结构化迁移。

重构方法论（强制）：

- 本次为绿地重建（greenfield rebuild），不参考、不继承既有 Flutter 架构分层与代码组织。
- 历史实现只作为“业务需求来源”，不能作为“结构设计来源”。
- 可以完全重命名模块、重设目录、重建协议，只要满足本文定义的行为与约束。

----------------------------------------------------------------------

## 1. 项目定位与现状（必须先理解）

NanoSync 是一个本地仓库中心化（repository-centric）的同步与版本管理工具，运行在 Windows 桌面。当前实现基于 Flutter + Fluent UI，核心关注点是：

- 本地目录注册为“仓库”
- 给仓库绑定远端连接（SMB / WebDAV / UNC）
- 做 fetch / push / pull / sync
- 做本地版本控制（自定义轻量 VCS）
- 自动化规则触发同步/提交
- 日志记录与问题排查

当前代码已经从“任务中心化”迁移为“仓库中心化”，但 README 仍残留旧描述（多任务同步那套）。重构时以真实代码行为为准，不以 README 为准。

----------------------------------------------------------------------

## 2. 当前系统总架构（逻辑分层）

### 2.1 入口与应用壳

- 入口：`lib/main.dart`
- 壳层导航：`lib/shared/widgets/app_shell.dart`

行为概述：

1. 启动窗口系统（window_manager）并设置窗口参数。
2. 启用 acrylic/mica 效果能力。
3. 初始化 SQLite FFI。
4. 预热版本库数据库（`nanosync_vc.db`）。
5. 检查自动化规则，存在启用规则才启动自动化 Runner。
6. 装载 Provider（主题管理 + 仓库选择状态），进入多页面导航。

导航页当前是 7 个：

1. 仓库页（RepositoryListPage）
2. 远程连接页（RemoteConnectionsPage）
3. 版本控制页（VersionControlPage）
4. 自动化页（AutomationPage）
5. 日志页（LogPage）
6. 设置页（SettingsPage）
7. 关于页（AboutPage）

### 2.2 数据存储

当前是双数据库：

- `nanosync.db`：应用主库（仓库注册、远端连接、远端绑定、同步记录、自动化规则、应用日志等）
- `nanosync_vc.db`：版本控制库（仓库分支提交树、暂存区、stash、远端跟踪、VC 同步记录）

重构后的硬性目标（高优先级，覆盖旧实现）：

- 仓库相关的所有业务数据必须由仓库自行存储（即仓库目录内自持久化）。
- 软件级数据库只允许保存两类全局信息：
	- 远程连接信息（`remote_connections` 语义）
	- 已注册仓库清单（`registered_repositories` 语义）
- 除上述两类信息外，禁止在软件级数据库中持久化任何仓库业务状态（包括但不限于提交树、同步记录、自动化规则、日志、仓库本地策略等）。

设备隔离约束（自动化与日志必须支持）：

- 仓库内保存的自动化规则必须携带设备指纹字段（`owner_device_fingerprint`）。
- 仓库内保存的日志记录必须携带设备指纹字段（`device_fingerprint`）。
- 默认执行策略：仅执行 `owner_device_fingerprint == 当前设备指纹` 的自动化规则。
- 默认展示策略：日志可跨设备查看，但必须可按设备指纹过滤。
- 导入策略：允许从其他设备导入自动化规则与日志，但导入后的规则默认不可直接生效，需要显式“接管/重绑定到本机指纹”后才可执行。

### 2.3 核心服务

- 仓库管理：`RepositoryManager`
- 远端连接管理：`RemoteConnectionManager`
- 同步引擎：`NewSyncEngine`
- 版本控制引擎：`VcEngine`
- 版本元数据跨端同步：`VcSyncService`
- 自动化规则：`AutomationService`
- 自动化执行器：`AutomationRunner`
- 协议实现：`SmbService` / `WebDAVService` / `UncService`
- 历史清理与容量估算：`HistoryCleaner` / `StorageEstimatorService`
- 应用日志：`AppLogService`

----------------------------------------------------------------------

## 3. 数据模型与数据库语义（重构时必须映射）

### 3.1 主库 nanosync.db（来自 DatabaseHelper）

核心表：

- `registered_repositories`
	- id
	- local_path（唯一）
	- name
	- last_accessed
	- added_at

- `remote_connections`
	- id
	- name（唯一）
	- protocol（smb/webdav/unc）
	- host
	- port
	- username
	- password
	- created_at
	- updated_at

- `repository_remotes`
	- id
	- repository_id
	- remote_name（关联 connection name）
	- remote_path
	- is_default
	- last_sync
	- last_fetch
	- created_at
	- UNIQUE(repository_id, remote_name)

- `repository_local_settings`
	- repository_id（PK）
	- max_versions
	- max_version_days
	- max_version_size_gb
	- created_at / updated_at

- `sync_logs`
	- id
	- task_id/task_name（历史命名遗留，实际已用于仓库同步语义）
	- start_time/end_time
	- total_files/success_count/fail_count/skip_count/conflict_count
	- status
	- error_message

还有自动化规则与应用日志等表（通过服务层按需初始化）。

### 3.2 VC 库 nanosync_vc.db（来自 VcDatabase）

核心表：

- `vc_repositories`
- `vc_branches`
- `vc_commits`
- `vc_tree_entries`
- `vc_file_changes`
- `vc_staging_entries`
- `vc_stashes`
- `vc_stash_entries`
- `vc_remotes`
- `vc_sync_records`
- `app_logs`

语义：

- 使用数据库保存“提交、树、变更、暂存区、stash”等信息。
- 工作目录里也维护 `.nanosync` 文件夹与 objects。
- `vc_remotes` 与 `vc_sync_records` 用于记录远端追踪与同步行为。

----------------------------------------------------------------------

## 4. 业务功能全景（按用户可见模块）

### 4.1 仓库管理模块

页面：`RepositoryListPage`

已实现能力：

- 列出注册仓库
- 按名称/路径搜索
- 新增仓库（导入本地目录）
- 克隆仓库（存在 stub 风险，后文详述）
- 删除仓库（可选删除 `.nanosync`）
- 迁移仓库路径
- 调整仓库默认远端绑定
- 查看 ahead/behind 状态（被动 fetch，且不写同步日志）
- 一键 sync
- 仓库级本地策略设置（历史保留参数）

关键逻辑细节：

- 卡片状态加载会调用 `NewSyncEngine.fetch(recordLog: false)`。
- 远端配置读取来自 `RemoteConnectionManager.getDefaultRepositoryRemote`。
- 仓库导入会确保：
	- 目录存在
	- `.nanosync` 初始化
	- 创建初始提交
	- 可选绑定默认远端
	- 保存仓库本地保留策略

### 4.2 远程连接模块

页面：`RemoteConnectionsPage`

已实现能力：

- 连接 CRUD
- 协议支持 SMB / UNC / WebDAV
- 连接测试（弹窗反馈）
- 显示连接地址、用户信息

关键逻辑：

- 连接名唯一。
- `testConnectionDirect` 按协议分流：
	- SMB：真实认证（strictCredentialCheck=true）
	- UNC：路径可达性检测
	- WebDAV：ping + 目录访问 + 可写测试

### 4.3 版本控制模块

页面：`VersionControlPage`

已实现能力：

- 选择仓库并加载状态
- 查看 staged / unstaged 变更
- 查看冲突列表
- 查看提交历史（limit 50）
- 分支管理入口
- stash 管理入口
- diff 查看器（工作区、暂存、提交差异）
- 冲突解决动作（按策略）

关键逻辑：

- 页面绑定 `VcEngine(repositoryId)`。
- 初始化时拉取仓库列表并自动绑定首个仓库。
- 所有操作完成后刷新全量状态。

### 4.4 自动化模块

页面：`AutomationPage`

已实现能力：

- 自动化规则 CRUD
- 规则启用/禁用
- 按仓库筛选规则
- 支持触发类型：定时 / 变更触发
- 支持动作类型：与同步、提交、推送组合相关
- 可配置重试次数与延迟

运行器行为（`AutomationRunner`）：

- 15 秒周期 tick
- 串行评估启用规则
- 每条规则失败隔离，避免拖垮整个 runner
- timeBased：按 interval 比较 lastTriggered
- changeBased：检查 `VcEngine.status()` 是否 dirty
- 支持 debounce 与重试执行

关键约束：

- 只有存在启用规则时才应启动 runner。
- 规则改动（创建/更新/删除/开关）后会同步 runner 启停状态。
- 每条规则必须绑定设备指纹；跨设备同步/导入后，默认处于“已导入未接管”状态，禁止自动执行。
- 提供“接管规则到当前设备”命令：将规则的 `owner_device_fingerprint` 更新为当前设备指纹并记录审计日志。

### 4.5 日志模块

页面：`LogPage`

已实现能力：

- 展示应用日志列表（最多 1000）
- 最小级别过滤（debug/info/warning/error/all）
- 关键词搜索（消息/分类/详情/来源/上下文等）
- 清空日志
- 展开查看详细上下文 JSON 与堆栈

重构新增硬性能力：

- 每条日志必须包含 `device_fingerprint`、`device_name`、`username`（可匿名化）等设备来源字段。
- 日志查询必须支持按设备指纹筛选、聚合与导出。
- 导入他设备日志时必须保留原始设备指纹，不可篡改来源。

### 4.6 设置模块

页面：`SettingsPage`

已实现能力：

- 主题模式切换（系统/浅色/深色）
- Mica 特效开关
- 开机自启（当前主要是 UI 状态）
- 最小化到托盘（当前主要是 UI 状态）
- 配置导入导出按钮（占位）
- 开源链接展示

----------------------------------------------------------------------

## 5. 同步与传输核心逻辑（必须完整迁移）

### 5.1 NewSyncEngine 核心职责

提供：`fetch`, `push`, `pull`, `sync`（组合）

行为摘要：

- 自动解析仓库的有效默认远端
- 建立协议连接（SMB/UNC/WebDAV）
- 下载/上传 `.nanosync/repository_state.json`
- 同步 objects 文件
- 更新远端跟踪时间（last_fetch/last_sync）
- 记录同步日志（可通过 recordLog 关闭）

`fetch` 关键流程：

1. 校验远端与连接
2. 下载远端 `repository_state.json`
3. `VcSyncService.importRepositoryState`
4. 计算 ahead/behind
5. 更新 last_fetch
6. 返回 FetchResult

`push` 关键流程：

1. 先 fetch（recordLog=false）
2. 若 behind>0 且非 force，拒绝推送
3. 收集需要上传的对象
4. 上传 objects
5. 导出并上传本地 repository_state
6. 上传 config.json（若存在）
7. 更新 last_sync

`pull` 关键流程：

1. 先 fetch（recordLog=false）
2. 若 behind==0，直接成功
3. 下载缺失 objects
4. 判断工作区状态：
	- clean 或 ahead==0：走 fast-forward/reset 流程
	- 否则执行 merge
5. 更新 last_sync

### 5.2 协议层实现

SMB（`SmbService`）：

- 强约束端口 445
- 使用 `smb_connect` 做认证连接
- `listShares` 用于严格凭证校验
- 支持上传/下载/删除/目录保证
- 远端路径要求带 share 段（例如 `/public/folder`）

WebDAV（`WebDAVService`）：

- 按端口推导 http/https
- 支持 noAuth/basicAuth
- 连接测试包含：ping、目录访问、可写性验证
- 文件上传后做存在性/长度等校验

UNC（`UncService`）：

- 面向 Windows 网络路径访问与测试

----------------------------------------------------------------------

## 6. 仓库与版本管理逻辑（必须保语义）

### 6.1 RepositoryManager

已实现：

- register / unregister / list / get / getByPath
- importExisting（导入现有目录）
- clone（克隆，当前下载步骤存在 stub）
- updateRepositoryConfig
- deleteRepository
- migrateRepository

导入仓库关键行为：

1. 规范化路径
2. 若 `.nanosync` 不存在则创建配置
3. 注册到主库
4. 确保 VC 库仓库存在
5. 初始化 VcEngine（若未初始化）
6. 自动 add + initial commit
7. 可选绑定默认远端
8. 写入仓库本地设置（保留参数）

### 6.2 VcEngine

核心语义：

- 初始化仓库会创建 `.nanosync`、objects、staging、ignore
- 提供 status/add/commit/log/diff/reset/branch/stash/conflict 等能力
- 依赖数据库记录提交树与变更索引

### 6.3 VcSyncService

职责：

- 导出仓库状态到 `.nanosync/repository_state.json`
- 导入远端状态并映射到本地 repo id
- 计算 ahead/behind
- 支持 remotes 和 sync_records 的迁移/融合

----------------------------------------------------------------------

## 7. 清理、容量、设备身份逻辑

### 7.1 历史清理（HistoryCleaner）

- 读取仓库配置 + 本地覆盖策略
- 计算当前提交数量、最老提交天数、objects 体积
- 判断是否达清理阈值
- 选保留提交集合
- 删除多余提交与无引用对象

### 7.2 存储估算（StorageEstimatorService）

- 扫描目录统计文本比例、小文件比例、平均大小
- 推导变更率并估算 retention 额外占用
- 受 maxVersions/maxDays/maxSizeGB 上限约束

### 7.3 设备身份（DeviceIdentity）

- 基于机器名、用户名、OS 信息、CPU/domain 等种子做 sha256 fingerprint
- 用于多设备同步上下文识别

----------------------------------------------------------------------

## 8. UI 与交互风格约束（迁移时只保行为，不强制保外观）

当前 UI 依赖 Fluent 组件与若干共享控件：

- SafeComboBox（防空列表弹出异常）
- 统一卡片、按钮、输入组件
- 各页头部 command bar 右对齐

重构为 TUI 后：

- 保留信息架构与操作路径
- 不需要复刻 GUI 样式细节
- 但要保留“任务反馈即时性”（进度、错误、成功提示）

----------------------------------------------------------------------

## 9. 已知缺陷与技术债（重构时必须修复）

以下是当前实现已知问题，迁移时视为必修项：

1. `RepositoryManager.clone` 下载流程是半成品：
	- `_downloadRepositoryConfig` 可能返回空
	- `_downloadObjects` 为空实现
	- 可能出现“克隆成功但无真实内容”

2. `NewSyncEngine._performMerge` 逻辑不完整：
	- 强制 WIP 提交
	- 直接覆盖工作目录
	- 冲突列表可能总为空
	- 缺乏真实三方合并/删除语义

3. `RemoteConnectionManager.bindToRepository` 对默认远端切换可能不彻底：
	- 设置已有远端为默认时，其他默认项可能没被清零

4. 主库 `sync_logs` 字段仍有 task 命名遗留，语义不干净。

5. 设置页部分功能仍是 UI 占位（如配置导入导出，系统层开机自启未完整落地）。

----------------------------------------------------------------------

## 10. 重构目标架构（Rust 版本）

### 10.1 进程拆分

必须拆分成两个 Rust 可执行体：

- nanosyncd（后台服务）
	- 常驻进程
	- 管理数据库、文件扫描、同步执行、自动化调度、日志
	- 对外提供 IPC API

- nanosync-tui（交互前端）
	- 纯终端界面
	- 负责展示状态、触发命令、订阅进度事件
	- 不直接操作底层存储与远程协议（全部通过服务）

### 10.2 IPC 约束

建议：

- Windows 命名管道或本地 unix-domain-socket（跨平台可抽象）
- 请求/响应 + 事件流双通道模型
- JSON-RPC 或自定义 typed protocol

需要支持：

- 命令：仓库/连接/同步/VC/自动化/设置/日志相关
- 流：同步进度事件、自动化执行事件、错误事件

### 10.3 数据层重建

数据主权约束（必须执行）：

- 仓库数据本地化：每个仓库独立保存自己的版本数据、同步元数据、自动化规则、日志与策略配置。
- 软件级数据库最小化：仅保留 `registered_repositories` 与 `remote_connections`。
- 软件层不得保存任何仓库状态缓存；如需性能优化，允许内存缓存，但必须可丢弃且不可持久化。

迁移策略：

- 先建立软件级最小 schema（仅仓库注册与远程连接）
- 为每个仓库建立仓库内数据文件布局（例如 `.nanosync/` 下的 db/json/log/index）
- 写迁移器：将旧主库/VC库中的仓库业务数据按 repository_id 拆分并落入对应仓库目录
- 保留旧字段兼容解析（包括 task 命名遗留），但迁移完成后不再写回软件级数据库

----------------------------------------------------------------------

## 11. Rust 实施要求（功能级验收清单）

请按以下验收条目交付：

1. 仓库管理
	- 注册/注销/迁移/删除
	- 导入现有目录并初始化 `.nanosync`
	- 克隆必须真实下载对象并可恢复工作区

2. 远端连接管理
	- SMB/WebDAV/UNC 连接 CRUD
	- 连接测试可返回可诊断错误
	- 默认远端切换必须保证唯一默认

3. 同步引擎
	- fetch/push/pull/sync
	- ahead/behind 计算
	- 进度事件
	- 可选日志记录开关

4. 版本控制
	- init/status/add/commit/log/diff/reset
	- branch/stash
	- 冲突检测与可视化策略
	- merge 至少支持正确三方合并基础能力

5. 自动化
	- 规则 CRUD
	- 定时与变更触发
	- runner 生命周期与启停
	- 重试与节流
	- 规则设备指纹绑定、跨设备导入、接管后生效机制

6. 日志体系
	- 结构化日志入库
	- 分级过滤与关键字检索
	- 与同步/自动化/协议层打通
	- 日志设备来源标记与跨设备导入保真

7. TUI
	- 页面映射原有七大模块
	- 主列表 + 详情 + 弹窗/确认流
	- 操作反馈（成功/失败/进度）

----------------------------------------------------------------------

## 12. 高优先级行为保持清单（迁移不可丢）

1. 仓库卡片状态读取时不应污染同步日志。
2. 仅当存在启用规则时自动化 runner 才会自动启动。
3. SMB 测试必须支持严格凭证检测，避免端口通即判成功。
4. 仓库本地保留策略属于“本机设置”，不跟随仓库同步。
5. 忽略规则支持 regex 语法（`re:`, `regex:`, `/.../`）。
6. 同步前后要做 VC 元数据导入导出，防止远端状态断裂。
7. 自动化规则必须设备指纹隔离，默认不得在非所有者设备自动生效。
8. 日志必须带设备指纹并支持跨设备导入与设备级检索。

----------------------------------------------------------------------

## 13. 可接受改动与不接受改动

可接受：

- UI 形态从 GUI 改为 TUI
- 内部模块重命名
- 单库化重构
- 协议层替换更稳定 Rust 库

不接受：

- 删除仓库中心化架构
- 去掉自动化与日志能力
- 去掉远端多协议支持
- 用“伪克隆/伪同步”替代真实对象传输
- 在软件级数据库中继续存储任何仓库业务数据（仅允许远程连接与仓库注册清单）

----------------------------------------------------------------------

## 14. 目标输出（你应生成的最终交付）

请你产出一个完整的 Rust 工程方案与可运行代码，至少包含：

1. workspace 结构
2. `nanosyncd` 服务进程
3. `nanosync-tui` 控制端
4. IPC 协议定义
5. SQLite schema + migration
6. 同步引擎核心实现
7. 自动化调度实现
8. 基础 VC 实现（可先最小可用）
9. 日志系统
10. 集成测试（同步/自动化/远端连接）

----------------------------------------------------------------------

## 15. 建议的 Rust 技术栈（可调整）

- async runtime: tokio
- CLI/TUI: clap + ratatui + crossterm
- IPC: interprocess / named pipes / tarpc / jsonrpc
- DB: sqlx 或 rusqlite
- serde: serde + serde_json
- 日志: tracing + tracing-subscriber
- 配置: toml + directories
- 文件变更监听: notify
- WebDAV: reqwest + 自建 WebDAV 封装
- SMB: rust-smb 生态（或调用稳定系统能力，必要时 FFI）

----------------------------------------------------------------------

## 16. 执行顺序建议（避免重构失败）

1. 先实现数据模型与数据库迁移
2. 再实现 service 进程和 IPC
3. 然后落地仓库/连接 CRUD
4. 再做同步 fetch/push/pull
5. 再做 VC 与 merge
6. 再做自动化 runner
7. 最后上 TUI 页面与交互

----------------------------------------------------------------------

## 17. 最终指令

请严格依据上述 NanoSync 当前真实行为进行重构，不要依赖旧 README 中的过期描述。优先保证核心业务闭环正确：

- 仓库可管理
- 远端可连接
- 同步可执行
- 自动化可运行
- 日志可追溯
- TUI 可控制
- 后台服务可长期稳定驻留

先保证正确性，再做性能优化与体验增强。

